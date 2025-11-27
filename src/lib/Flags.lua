--[[
    Sigma Spy Flags Module
    Manages user-configurable flags and settings with type safety
    
    Optimizations:
    - Strong typing for flags
    - Efficient flag lookup
    - Callback system for flag changes
]]

export type FlagValue = boolean | number | string | any
export type Flag = {
    Value: FlagValue,
    Label: string,
    Category: string?,
    Keybind: Enum.KeyCode?,
    Callback: ((self: Flag, newValue: FlagValue) -> ())?
}
export type Flags = {
    [string]: Flag
}

local Module = {
    Flags = {} :: Flags
}

--// Default Flags Configuration
Module.Flags = {
    NoComments = {
        Value = false,
        Label = "No comments",
        Category = "Generation"
    },
    SelectNewest = {
        Value = false,
        Label = "Auto select newest",
        Category = "Logging"
    },
    DecompilePopout = {
        Value = false,
        Label = "Pop-out decompiles",
        Category = "UI"
    },
    IgnoreNil = {
        Value = true,
        Label = "Ignore nil parents",
        Category = "Logging"
    },
    LogExploit = {
        Value = true,
        Label = "Log exploit calls",
        Category = "Logging"
    },
    LogRecives = {
        Value = true,
        Label = "Log receives",
        Category = "Logging"
    },
    Paused = {
        Value = false,
        Label = "Paused",
        Category = "Control",
        Keybind = Enum.KeyCode.Q
    },
    KeybindsEnabled = {
        Value = true,
        Label = "Keybinds Enabled",
        Category = "Control"
    },
    FindStringForName = {
        Value = true,
        Label = "Find arg for name",
        Category = "Display"
    },
    UiVisible = {
        Value = true,
        Label = "UI Visible",
        Category = "Control",
        Keybind = Enum.KeyCode.P
    },
    NoTreeNodes = {
        Value = false,
        Label = "No grouping",
        Category = "Display"
    },
    TableArgs = {
        Value = false,
        Label = "Table args",
        Category = "Generation"
    },
    NoVariables = {
        Value = false,
        Label = "No compression",
        Category = "Generation"
    }
}

--[[
    Gets the current value of a flag
    @param Name string - The name of the flag
    @return FlagValue - The current value of the flag
]]
function Module:GetFlagValue(Name: string): FlagValue
    local Flag = self:GetFlag(Name)
    return Flag.Value
end

--[[
    Sets the value of a flag and triggers its callback if defined
    @param Name string - The name of the flag
    @param Value FlagValue - The new value to set
]]
function Module:SetFlagValue(Name: string, Value: FlagValue)
    local Flag = self:GetFlag(Name)
    local OldValue = Flag.Value
    Flag.Value = Value
    
    --// Trigger callback if value changed
    if OldValue ~= Value and Flag.Callback then
        local success, err = pcall(Flag.Callback, Flag, Value)
        if not success then
            warn("[Flags] Callback error for", Name, ":", err)
        end
    end
end

--[[
    Toggles a boolean flag
    @param Name string - The name of the flag to toggle
    @return boolean - The new value after toggling
]]
function Module:ToggleFlag(Name: string): boolean
    local Flag = self:GetFlag(Name)
    
    if typeof(Flag.Value) ~= "boolean" then
        warn("[Flags] Cannot toggle non-boolean flag:", Name)
        return Flag.Value
    end
    
    local NewValue = not Flag.Value
    self:SetFlagValue(Name, NewValue)
    
    return NewValue
end

--[[
    Sets the callback function for a flag
    @param Name string - The name of the flag
    @param Callback function - The callback to invoke when the flag changes
]]
function Module:SetFlagCallback(Name: string, Callback: (self: Flag, newValue: FlagValue) -> ())
    local Flag = self:GetFlag(Name)
    Flag.Callback = Callback
end

--[[
    Sets multiple flag callbacks at once
    @param Dict table - Dictionary mapping flag names to callbacks
]]
function Module:SetFlagCallbacks(Dict: {[string]: (self: Flag, newValue: FlagValue) -> ()})
    for Name, Callback in next, Dict do 
        self:SetFlagCallback(Name, Callback)
    end
end

--[[
    Gets a flag by name
    @param Name string - The name of the flag
    @return Flag - The flag object
]]
function Module:GetFlag(Name: string): Flag
    local AllFlags = self:GetFlags()
    local Flag = AllFlags[Name]
    
    assert(Flag, string.format("[Flags] Flag '%s' does not exist!", Name))
    
    return Flag
end

--[[
    Safely gets a flag, returning nil if it doesn't exist
    @param Name string - The name of the flag
    @return Flag? - The flag object or nil
]]
function Module:TryGetFlag(Name: string): Flag?
    local AllFlags = self:GetFlags()
    return AllFlags[Name]
end

--[[
    Adds a new flag to the system
    @param Name string - The name of the flag
    @param Flag Flag - The flag configuration
]]
function Module:AddFlag(Name: string, Flag: Flag)
    local AllFlags = self:GetFlags()
    
    if AllFlags[Name] then
        warn("[Flags] Overwriting existing flag:", Name)
    end
    
    AllFlags[Name] = Flag
end

--[[
    Removes a flag from the system
    @param Name string - The name of the flag to remove
    @return boolean - Whether the flag was removed
]]
function Module:RemoveFlag(Name: string): boolean
    local AllFlags = self:GetFlags()
    
    if not AllFlags[Name] then
        return false
    end
    
    AllFlags[Name] = nil
    return true
end

--[[
    Gets all flags
    @return Flags - The flags dictionary
]]
function Module:GetFlags(): Flags
    return self.Flags
end

--[[
    Gets all flags in a specific category
    @param Category string - The category to filter by
    @return Flags - Flags in the specified category
]]
function Module:GetFlagsByCategory(Category: string): Flags
    local Result = {}
    
    for Name, Flag in next, self.Flags do
        if Flag.Category == Category then
            Result[Name] = Flag
        end
    end
    
    return Result
end

--[[
    Serializes all flags to a table (for saving)
    @return table - Dictionary of flag names to values
]]
function Module:Serialize(): {[string]: FlagValue}
    local Data = {}
    
    for Name, Flag in next, self.Flags do
        Data[Name] = Flag.Value
    end
    
    return Data
end

--[[
    Deserializes flag values from a table (for loading)
    @param Data table - Dictionary of flag names to values
]]
function Module:Deserialize(Data: {[string]: FlagValue})
    for Name, Value in next, Data do
        local Flag = self:TryGetFlag(Name)
        
        if Flag and typeof(Flag.Value) == typeof(Value) then
            self:SetFlagValue(Name, Value)
        end
    end
end

--[[
    Resets all flags to their default values
]]
function Module:ResetToDefaults()
    --// Store default values statically
    local Defaults = {
        NoComments = false,
        SelectNewest = false,
        DecompilePopout = false,
        IgnoreNil = true,
        LogExploit = true,
        LogRecives = true,
        Paused = false,
        KeybindsEnabled = true,
        FindStringForName = true,
        UiVisible = true,
        NoTreeNodes = false,
        TableArgs = false,
        NoVariables = false
    }
    
    for Name, DefaultValue in next, Defaults do
        local Flag = self:TryGetFlag(Name)
        if Flag then
            self:SetFlagValue(Name, DefaultValue)
        end
    end
end

return Module
