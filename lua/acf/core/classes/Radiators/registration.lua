local Classes   = ACF.Classes
local Radiators = Classes.Radiators
local Entries   = {}


function Radiators.Register(ID, Data)
	local Group = Classes.AddGroup(ID, Entries, Data)

	if not Group.LimitConVar then
		Group.LimitConVar = {
			Name   = "_acf_radiator",
			Amount = 16,
			Text   = "Maximum amount of ACF radiators a player can create."
		}
	end

	Classes.AddSboxLimit(Group.LimitConVar)

	return Group
end

function Radiators.RegisterItem(ID, ClassID, Data)
	local Class = Classes.AddGroupItem(ID, ClassID, Entries, Data)

	if Class.Name == nil then
		Class.Name = ID
	end

	return Class
end

Classes.AddGroupedFunctions(Radiators, Entries)
