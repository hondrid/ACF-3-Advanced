local ACF = ACF
local Classes = ACF.Classes
local Radiators = Classes.Radiators
local RadiatorSize    = Vector()

local function CreateMenu(Menu)
	local Entries = Radiators.GetEntries()
	local RadiatorsByType = Entries["Rad_B"].Items
	ACF.SetClientData("RadiatorName", RadiatorsByType[1].Name)
	ACF.SetClientData("RadiatorType", "Rad_B")
	Menu:AddTitle("Radiator Settings")

	local RadiatorType = Menu:AddComboBox()
	local Radiator = Menu:AddComboBox()

	local RadiatorBase = Menu:AddCollapsible("Radiator Information")
	local RadiatorDesc = RadiatorBase:AddLabel()
	local RadPreview = RadiatorBase:AddModelPreview(nil, true)
	local RadiatorInfo = RadiatorBase:AddLabel()

	ACF.SetClientData("PrimaryClass", "acf_radiator")
	ACF.SetClientData("SecondaryClass", "")

	ACF.SetToolMode("acf_menu", "Spawner", "Radiator")

	ACF.LoadSortedList(RadiatorType, Entries, "ID")
	ACF.LoadSortedList(Radiator, RadiatorsByType, "Name")
	
	function Radiator:OnSelect(Index, _, Data)
		if self.Selected == Data then return end
		local CurRadiator = RadiatorsByType[Index]
		
		ACF.SetClientData("RadiatorName", CurRadiator.Name)
		ACF.SetClientData("RadiatorType", CurRadiator.ClassID)
		ACF.SetClientData("RadiatorSize", CurRadiator.Size)
		self.ListData.Index = Index
		self.Selected = Data

		local ClassData = Radiator.Selected
		local ClassDesc = ClassData.Description

		self.Description = (ClassDesc and (ClassDesc .. "\n\n") or "")
		if Data.Description then
			self.Description = self.Description .. Data.Description
		end

		local Model = Data.Model or ClassData.Model
		local Material = Data.Material or ClassData.Material

		RadPreview:UpdateModel(Model, Material)
		RadPreview:UpdateSettings(Data.Preview or ClassData.Preview)

		RadiatorType:UpdateRadiatorText()
	end
	
	function RadiatorType:OnSelect(Index, _, Data)
		if self.Selected == Data then return end
		self.ListData.Index = Index
		
		RadiatorsByType = Entries[Data.ID].Items
		
		ACF.SetClientData("RadiatorType",Data.ID)
		ACF.LoadSortedList(Radiator, RadiatorsByType, "Name")
		
	end
	
	function RadiatorType:UpdateRadiatorText()
		if not self.Selected then return end

		local CurRadiator = Radiator.Selected
		if not CurRadiator then
			CurRadiator = RadiatorType.Select
		end
		
		local RadiatorFunc = self.Selected.RadiatorText
		local RadiatorText = ""
		local RadiatorDescText = ""

		local Wall = ACF.FuelArmor * ACF.MmToInch -- Wall thickness in inches
		local ClassData = RadiatorType.Selected
		local Volume, Area

		if ClassData.CalcVolume then
			Volume, Area = ClassData.CalcVolume(RadiatorSize, Wall)
		else
			Area = CurRadiator.SurfaceArea
			Volume = CurRadiator.Volume - (CurRadiator.SurfaceArea * Wall) -- Total volume of tank (cu in), reduced by wall thickness
		end

		if ClassData.RadiatorDescText then
			RadiatorDescText = ClassData.RadiatorDescText()
		else
			RadiatorDescText = ""
		end

		local Capacity	= Volume * ACF.gCmToKgIn * ACF.TankVolumeMul -- Internal volume available for fuel in liters
		local EmptyMass	= Area * Wall * 16.387 * 0.0079 -- Total wall volume * cu in to cc * density of steel (kg/cc)
		local Mass		= EmptyMass + Capacity * ACF.RadiatorCoolantDensity -- Weight of tank + weight of fuel

		if TextFunc then
			RadiatorText = RadiatorText .. TextFunc(Capacity, Mass, EmptyMass)
		else
			local Text = "Radiator Armor : %s mm\nCapacity : %s L - %s gal\nFull Mass : %s\nEmpty Mass : %s"
			local Liters = math.Round(Capacity, 2)
			local Gallons = math.Round(Capacity * 0.264172, 2)

			RadiatorText = RadiatorText .. Text:format(ACF.FuelArmor, Liters, Gallons, ACF.GetProperMass(Mass), ACF.GetProperMass(EmptyMass))
		end

		if CurRadiator.Unlinkable then
			RadiatorText = RadiatorText .. "\n\nThis Radiator cannot be linked to other ACF entities."
		end

		RadiatorDesc:SetText(ClassData.Description .. RadiatorDescText)
		RadiatorInfo:SetText(RadiatorText)
	end
	
end

ACF.AddMenuItem(3333, "Entities", "Radiators", "cog", CreateMenu)
