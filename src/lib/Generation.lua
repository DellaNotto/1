--[[
    Sigma Spy Generation Module
    Handles code generation, script templating, and log dumping
    
    Optimizations:
    - Improved template system
    - Better code formatting
    - Enhanced variable management
    - More efficient string building
]]

export type RemoteData = {
    Remote: Instance,
    IsReceive: boolean?,
    MetaMethod: string,
    Args: {any},
    Method: string,
    TransferType: string,
    ValueReplacements: {[any]: any}?,
    NoVariables: boolean?
}

export type CallInfo = {
    Arguments: {any}?,
    Indent: number?,
    RemoteVariable: string,
    Module: any
}

export type ScriptData = {
    Variables: {[string]: any},
    MetaMethod: string
}

local Generation = {
    DumpBaseName = "SigmaSpy-Dump %s.lua",
    Header = "-- Generated with Sigma Spy\n-- Github: https://github.com/depthso/Sigma-Spy\n",
    
    ScriptTemplates = {
        ["Remote"] = {
            {"%RemoteCall%"}
        },
        ["Spam"] = {
            {"while task.wait() do"},
            {"%RemoteCall%", 2},
            {"end"}
        },
        ["Repeat"] = {
            {"for Index = 1, 10 do"},
            {"%RemoteCall%", 2},
            {"end"}
        },
        ["Block"] = {
            ["__index"] = {
                {"local Old; Old = hookfunction(%Signal%, function(self, ...)"},
                {"if self == %Remote% then", 2},
                {"return", 3},
                {"end", 2},
                {"return Old(self, ...)", 2},
                {"end)"}
            },
            ["__namecall"] = {
                {"local Old; Old = hookmetamethod(game, \"__namecall\", function(self, ...)"},
                {"local Method = getnamecallmethod()", 2},
                {"if self == %Remote% and Method == \"%Method%\" then", 2},
                {"return", 3},
                {"end", 2},
                {"return Old(self, ...)", 2},
                {"end)"}
            },
            ["Connect"] = {
                {"for _, Connection in getconnections(%Signal%) do"},
                {"Connection:Disable()", 2},
                {"end"}
            }
        }
    },
    
    SwapsCallback = nil :: ((Interface: any) -> ())?
}

--// Modules
local Config
local Hook
local ParserModule
local Flags
local ThisScript = script

--// Localized functions
local table_insert = table.insert
local table_concat = table.concat
local table_clear = table.clear
local table_find = table.find
local string_format = string.format
local string_rep = string.rep
local string_gsub = string.gsub
local math_clamp = math.clamp
local math_random = math.random
local typeof = typeof
local next = next
local pcall = pcall

--[[
    Merges source table into base table
    @param Base table - The base table
    @param New table? - The source table
]]
local function Merge(Base: {[any]: any}, New: {[any]: any}?)
    if not New then 
        return 
    end
    
    for Key, Value in next, New do
        Base[Key] = Value
    end
end

--[[
    Initializes the Generation module
    @param Data table - Initialization data
]]
function Generation:Init(Data: {Modules: {[string]: any}})
    local ModulesTable = Data.Modules
    local Configuration = ModulesTable.Configuration

    --// Store module references
    Config = ModulesTable.Config
    Hook = ModulesTable.Hook
    Flags = ModulesTable.Flags
    
    --// Import parser
    local ParserUrl = Configuration.ParserUrl
    self:LoadParser(ParserUrl)
end

--[[
    Makes a string printable by escaping non-printable characters
    @param String string - The string to process
    @return string - The printable string
]]
function Generation:MakePrintable(String: string): string
    if not ParserModule then
        return String
    end
    
    local Formatter = ParserModule.Modules.Formatter
    return Formatter:MakePrintable(String)
end

--[[
    Adds a timestamp to a file path
    @param FilePath string - The file path template
    @return string - The timestamped path
]]
function Generation:TimeStampFile(FilePath: string): string
    local TimeStamp = os.date("%Y-%m-%d_%H-%M-%S")
    return string_format(FilePath, TimeStamp)
end

--[[
    Writes content to a dump file with timestamp
    @param Content string - The content to write
    @return string - The file path
]]
function Generation:WriteDump(Content: string): string
    local DumpBaseName = self.DumpBaseName
    local FilePath = self:TimeStampFile(DumpBaseName)

    local Success, Error = pcall(writefile, FilePath, Content)
    
    if not Success then
        warn("[Generation] Failed to write dump:", Error)
    end

    return FilePath
end

--[[
    Loads the parser module from URL
    @param ModuleUrl string - The URL to load from
]]
function Generation:LoadParser(ModuleUrl: string)
    local Success, Result = pcall(function()
        return loadstring(game:HttpGet(ModuleUrl), "Parser")()
    end)
    
    if Success then
        ParserModule = Result
    else
        warn("[Generation] Failed to load parser:", Result)
    end
end

--[[
    Creates a new value swaps table
    @return table - The replacements table
]]
function Generation:MakeValueSwapsTable(): {[any]: any}
    if not ParserModule then
        return {}
    end
    
    local Formatter = ParserModule.Modules.Formatter
    return Formatter:MakeReplacements()
end

--[[
    Sets the callback for getting value swaps
    @param Callback function - The callback function
]]
function Generation:SetSwapsCallback(Callback: (Interface: any) -> ())
    self.SwapsCallback = Callback
end

--[[
    Gets the base code with header and variables
    @param Module any - The parser module
    @return string - The base code
    @return boolean - Whether there are no variables
]]
function Generation:GetBase(Module: any): (string, boolean)
    local NoComments = Flags:GetFlagValue("NoComments")
    local Header = self.Header

    local Code = NoComments and "" or Header

    --// Generate variables code
    local Variables = Module.Parser:MakeVariableCode({
        "Services", "Remote", "Variables"
    }, NoComments)

    local NoVariables = Variables == ""
    Code = Code .. Variables

    return Code, NoVariables
end

--[[
    Gets the current value swaps
    @return table - The swaps dictionary
]]
function Generation:GetSwaps(): {[Instance]: {String: string, NextParent: Instance?}}
    local Func = self.SwapsCallback
    local Swaps = {}

    if not Func then
        return Swaps
    end

    local Interface = {}
    
    function Interface:AddSwap(Object: Instance, Data: {String: string, NextParent: Instance?})
        if not Object then 
            return 
        end
        Swaps[Object] = Data
    end

    --// Invoke callback
    local Success, Error = pcall(Func, Interface)
    
    if not Success then
        warn("[Generation] Swaps callback error:", Error)
    end

    return Swaps
end

--[[
    Picks a random variable name from config
    @return string - The variable name template
]]
function Generation:PickVariableName(): string
    local Names = Config.VariableNames
    return Names[math_random(1, #Names)]
end

--[[
    Creates a new parser instance
    @param Extra table? - Extra configuration
    @return any - The parser module instance
]]
function Generation:NewParser(Extra: {[string]: any}?): any
    if not ParserModule then
        error("[Generation] Parser not loaded!")
    end
    
    local VariableName = self:PickVariableName()
    local Swaps = self:GetSwaps()

    local Configuration = {
        VariableBase = VariableName,
        Swaps = Swaps,
        IndexFunc = function(...)
            return Hook:Index(...)
        end,
    }

    --// Merge extra configuration
    Merge(Configuration, Extra)

    --// Create new parser instance
    return ParserModule:New(Configuration)
end

--[[
    Creates an indent string
    @param IndentString string - The current indent
    @param Line string - The line to indent
    @return string - The indented line
]]
function Generation:Indent(IndentString: string, Line: string): string
    return IndentString .. Line
end

--[[
    Generates a remote call script
    @param Data RemoteData - The remote data
    @param Info CallInfo - Call information
    @return string - The generated code
]]
function Generation:CallRemoteScript(Data: RemoteData, Info: CallInfo): string
    local IsReceive = Data.IsReceive
    local Method = Data.Method
    local Args = Data.Args

    local RemoteVariable = Info.RemoteVariable
    local Indent = Info.Indent or 0
    local Module = Info.Module

    local Variables = Module.Variables
    local Parser = Module.Parser
    local NoVariables = Data.NoVariables

    local IndentString = self:MakeIndent(Indent)

    --// Parse arguments
    local ParsedArgs, ItemsCount, IsArray = Parser:ParseTableIntoString({
        NoBrackets = true,
        NoVariables = NoVariables,
        Table = Args,
        Indent = Indent
    })

    --// Create table variable if not an array
    if not IsArray or NoVariables then
        ParsedArgs = Variables:MakeVariable({
            Value = string_format("{%s}", ParsedArgs),
            Comment = not IsArray and "Arguments aren't ordered" or nil,
            Name = "RemoteArgs",
            Class = "Remote"
        })
    end

    --// Wrap in unpack if table is a dict
    if ItemsCount > 0 and not IsArray then
        ParsedArgs = string_format("unpack(%s, 1, table.maxn(%s))", ParsedArgs, ParsedArgs)
    end

    --// FireSignal script for client receives
    if IsReceive then
        local Second = ItemsCount <= 0 and "" or ", " .. ParsedArgs
        local Signal = string_format("%s.%s", RemoteVariable, Method)

        local Code = "-- This data was received from the server"
        Code = Code .. "\n" .. IndentString .. string_format("firesignal(%s%s)", Signal, Second)
        
        return Code
    end
    
    --// Remote invoke script
    return string_format("%s:%s(%s)", RemoteVariable, Method, ParsedArgs)
end

--[[
    Applies variable substitutions to a string
    @param String string - The template string
    @param Variables table - Variable values
    @param ... any - Additional arguments for function values
    @return string - The processed string
]]
function Generation:ApplyVariables(String: string, Variables: {[string]: any}, ...: any): string
    local Args = {...}
    
    for Variable, Value in next, Variables do
        --// Invoke value function if needed
        if typeof(Value) == "function" then
            Value = Value(unpack(Args))
        end

        String = string_gsub(String, "%%" .. Variable .. "%%", function()
            return tostring(Value)
        end)
    end
    
    return String
end

--[[
    Creates an indent string of specified level
    @param IndentLevel number - The indent level
    @return string - The indent string
]]
function Generation:MakeIndent(IndentLevel: number): string
    return string_rep("\t", IndentLevel)
end

--[[
    Generates code from a script template
    @param ScriptType string - The template type
    @param Data ScriptData - Script data
    @return string - The generated code
]]
function Generation:MakeCallCode(ScriptType: string, Data: ScriptData): string
    local ScriptTemplates = self.ScriptTemplates
    local Template = ScriptTemplates[ScriptType]

    assert(Template, string_format("[Generation] '%s' is not a valid script type!", ScriptType))

    local Variables = Data.Variables
    local MetaMethod = Data.MetaMethod
    local MetaMethods = {"__index", "__namecall", "Connect"}

    local function Compile(TemplateData: {any}): string
        local Parts = {}

        for Key, Value in next, TemplateData do
            --// Check for metamethod-specific templates
            local IsMetaTypeOnly = table_find(MetaMethods, Key)
            
            if IsMetaTypeOnly then
                if Key == MetaMethod then
                    local Line = Compile(Value)
                    table_insert(Parts, Line)
                end
                continue
            end

            --// Extract line info
            local Content, IndentLevel = Value[1], Value[2] or 0
            IndentLevel = math_clamp(IndentLevel - 1, 0, 9999)

            --// Generate line
            local Line = self:ApplyVariables(Content, Variables, IndentLevel)
            local IndentString = self:MakeIndent(IndentLevel)

            table_insert(Parts, IndentString .. Line .. "\n")
        end

        return table_concat(Parts)
    end
    
    return Compile(Template)
end

--[[
    Generates a complete remote script
    @param Module any - The parser module
    @param Data RemoteData - Remote data
    @param ScriptType string - The script type
    @return string - The generated script
]]
function Generation:RemoteScript(Module: any, Data: RemoteData, ScriptType: string): string
    --// Extract data
    local Remote = Data.Remote
    local Args = Data.Args
    local Method = Data.Method
    local MetaMethod = Data.MetaMethod

    --// Remote info
    local ClassName = Hook:Index(Remote, "ClassName")
    local IsNilParent = Hook:Index(Remote, "Parent") == nil
    
    local Variables = Module.Variables
    local Formatter = Module.Formatter
    
    --// Pre-render variables
    Variables:PrerenderVariables(Args, {"Instance"})

    --// Create remote variable
    local RemoteVariable = Variables:MakeVariable({
        Value = Formatter:Format(Remote, {
            NoVariables = true
        }),
        Comment = string_format("%s%s", ClassName, IsNilParent and " | Remote parent is nil" or ""),
        Name = Formatter:MakeName(Remote),
        Lookup = Remote,
        Class = "Remote"
    })

    --// Generate call script
    local CallCode = self:MakeCallCode(ScriptType, {
        Variables = {
            ["RemoteCall"] = function(IndentLevel: number)
                return self:CallRemoteScript(Data, {
                    RemoteVariable = RemoteVariable,
                    Indent = IndentLevel,
                    Module = Module
                })
            end,
            ["Remote"] = RemoteVariable,
            ["Method"] = Method,
            ["Signal"] = string_format("%s.%s", RemoteVariable, Method)
        },
        MetaMethod = MetaMethod
    })
    
    --// Build final code
    local Code = self:GetBase(Module)
    return Code .. "\n" .. CallCode
end

--[[
    Gets connections table for a signal
    @param Signal RBXScriptSignal - The signal
    @return table - Array of connection data
]]
function Generation:ConnectionsTable(Signal: RBXScriptSignal): {{Function: (...any) -> ...any, State: string, Script: Instance?}}
    local Success, Connections = pcall(getconnections, Signal)
    
    if not Success then
        return {}
    end
    
    local DataArray = {}

    for _, Connection in next, Connections do
        local Function = Connection.Function
        
        if not Function then
            continue
        end
        
        local EnvSuccess, Env = pcall(getfenv, Function)
        
        if not EnvSuccess then
            continue
        end
        
        local Script = rawget(Env, "script")

        --// Skip if from this script
        if Script == ThisScript then 
            continue 
        end

        local Data = {
            Function = Function,
            State = Connection.State,
            Script = Script
        }

        table_insert(DataArray, Data)
    end

    return DataArray
end

--[[
    Generates a table script
    @param Module any - The parser module
    @param Table table - The table to serialize
    @return string - The generated script
]]
function Generation:TableScript(Module: any, Table: {[any]: any}): string
    --// Pre-render variables
    Module.Variables:PrerenderVariables(Table, {"Instance"})

    --// Parse table
    local ParsedTable = Module.Parser:ParseTableIntoString({
        Table = Table
    })

    --// Generate script
    local Code, NoVariables = self:GetBase(Module)
    local Separator = NoVariables and "" or "\n"
    
    return Code .. Separator .. "return " .. ParsedTable
end

--[[
    Creates a types table for a given table
    @param Table table - The source table
    @return table - Table of type names
]]
function Generation:MakeTypesTable(Table: {[any]: any}): {[any]: any}
    local Types = {}

    for Key, Value in next, Table do
        local Type = typeof(Value)
        
        if Type == "table" then
            Type = self:MakeTypesTable(Value)
        end

        Types[Key] = Type
    end

    return Types
end

--[[
    Gets connection info for a remote
    @param Remote Instance - The remote
    @param ClassData table - Class data with receive methods
    @return table? - Connection information
]]
function Generation:ConnectionInfo(Remote: Instance, ClassData: {Receive: {string}?}): {[string]: any}?
    local ReceiveMethods = ClassData.Receive
    if not ReceiveMethods then 
        return nil
    end

    local Connections = {}
    
    for _, Method in next, ReceiveMethods do
        local Success, Signal = pcall(function()
            return Hook:Index(Remote, Method)
        end)
        
        if Success and Signal then
            Connections[Method] = self:ConnectionsTable(Signal)
        end
    end

    return Connections
end

--[[
    Generates advanced info script
    @param Module any - The parser module
    @param Data table - Remote data
    @return string - The generated script
]]
function Generation:AdvancedInfo(Module: any, Data: {
    CallingFunction: ((...any) -> ...any)?,
    ClassData: {[string]: any},
    Remote: Instance,
    Args: {any},
    SourceScript: Instance?,
    CallingScript: Instance?,
    Id: string,
    Method: string,
    MetaMethod: string,
    IsActor: boolean?
}): string
    --// Extract data
    local Function = Data.CallingFunction
    local ClassData = Data.ClassData
    local Remote = Data.Remote
    local Args = Data.Args
    
    --// Build info table
    local FunctionInfo = {
        ["Caller"] = {
            ["SourceScript"] = Data.SourceScript,
            ["CallingScript"] = Data.CallingScript,
            ["CallingFunction"] = Function
        },
        ["Remote"] = {
            ["Remote"] = Remote,
            ["RemoteID"] = Data.Id,
            ["Method"] = Data.Method,
            ["Connections"] = self:ConnectionInfo(Remote, ClassData)
        },
        ["Arguments"] = {
            ["Length"] = #Args,
            ["Types"] = self:MakeTypesTable(Args),
        },
        ["MetaMethod"] = Data.MetaMethod,
        ["IsActor"] = Data.IsActor,
    }

    --// Add debug info if function is a Lua closure
    if Function and islclosure and islclosure(Function) then
        local Success, Upvalues = pcall(debug.getupvalues, Function)
        if Success then
            FunctionInfo["UpValues"] = Upvalues
        end
        
        Success, Constants = pcall(debug.getconstants, Function)
        if Success then
            FunctionInfo["Constants"] = Constants
        end
    end

    return self:TableScript(Module, FunctionInfo)
end

--[[
    Dumps logs to a file
    @param Logs table - Array of log entries
    @return string - The file path
]]
function Generation:DumpLogs(Logs: {{Args: {any}, Timestamp: number, ReturnValues: {any}?, Method: string, MetaMethod: string, CallingScript: Instance?, Remote: Instance?}}): string
    local BaseData
    local Parsed = {
        Remote = nil,
        Calls = {}
    }

    --// Create parser instance
    local Module = self:NewParser()

    for _, Data in next, Logs do
        local Calls = Parsed.Calls
        local Entry = {
            Args = Data.Args,
            Timestamp = Data.Timestamp,
            ReturnValues = Data.ReturnValues,
            Method = Data.Method,
            MetaMethod = Data.MetaMethod,
            CallingScript = Data.CallingScript,
        }

        table_insert(Calls, Entry)

        --// Set base data from first entry
        if not BaseData then
            BaseData = Data
        end
    end

    --// Set remote from base data
    if BaseData then
        Parsed.Remote = BaseData.Remote
    end

    --// Compile and save
    local Output = self:TableScript(Module, Parsed)
    local FilePath = self:WriteDump(Output)
    
    return FilePath
end

return Generation
