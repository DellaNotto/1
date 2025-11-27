--[[
    Sigma Spy Return Spoofs Module
    Configure custom return values for specific remotes
    
    Usage:
    - The Return table will be unpacked for the response
    - If Return is a function, it receives (OriginalFunc, ...) where ... are the original arguments
    
    Examples:
    [game.ReplicatedStorage.Remotes.Example] = {
        Method = "FireServer",
        Return = {"Hello world from Sigma Spy!"}
    }
    
    [game.ReplicatedStorage.Remotes.Dynamic] = {
        Method = "InvokeServer",
        Return = function(OriginalFunc, ...)
            local args = {...}
            -- You can call OriginalFunc(...) to get the real return value
            return {"Modified", "Return", "Values"}
        end
    }
]]

export type ReturnSpoof = {
    Method: string,
    Return: {any} | (originalFunc: (...any) -> ...any, ...any) -> {any}
}

export type ReturnSpoofs = {
    [Instance]: ReturnSpoof
}

local Spoofs: ReturnSpoofs = {
    -- Add your return spoofs here
    -- Example:
    -- [game.ReplicatedStorage.Remotes.MyRemote] = {
    --     Method = "FireServer",
    --     Return = {"Spoofed response!"}
    -- }
}

return Spoofs
