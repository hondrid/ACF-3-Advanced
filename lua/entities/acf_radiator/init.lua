AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

--[[
	Radiators have coolant, heat dispersion rate, heat dispersion ratio, damage, depletion on damage.

--===============================================================================================--
-- Radiator class setup
--===============================================================================================--]]--


--===============================================================================================--
-- Local Funcs and Vars
--===============================================================================================--

local Damage      = ACF.Damage
local Contraption = ACF.Contraption
local Objects     = Damage.Objects
local ActiveRadiators = ACF.Radiators
local Utilities   = ACF.Utilities
local Clock       = Utilities.Clock
local Sounds      = Utilities.Sounds
local RefillDist  = ACF.RefillDistance * ACF.RefillDistance
local TimerCreate = timer.Create
local TimerExists = timer.Exists
local TimerRemove = timer.Remove
local Clamp       = math.Clamp
local Round       = math.Round
local HookRun     = hook.Run

local function CanRefill(Refill, Radiator, Distance)
	if Refill == Radiator then return false end
	if Radiator.Disabled then return false end
	if Radiator.SupplyCoolant then return false end
	if Radiator.Coolant >= Radiator.Capacity then return false end

	return Distance <= RefillDist
end

--===============================================================================================--

do -- Spawn and Update functions
	local Classes   = ACF.Classes
	local WireIO    = Utilities.WireIO
	local Entities  = Classes.Entities
	local Radiators = Classes.Radiators

	local Inputs = {
		"Active (If set to a non-zero value, it'll allow engines to consume coolant from this coolant tank.)",
		"Coolant Tank (If set to a non-zero value, this coolant tank will refill surrounding tanks that contain the same coolant type.)",
	}
	local Outputs = {
		"Activated (Whether or not this coolant tank is able to be used by an engine.)",
		"Coolant (Amount of coolant currently in the tank, in liters or kWh)",
		"Capacity (Total amount of coolant the tank can hold, in liters or kWh)",
		"Leaking (Returns 1 if the coolant tank is currently losing coolant.)",
		"Temperature (Current Temperature in degrees C)",
		"Entity (The coolant tank itself.) [ENTITY]"
	}

	local function VerifyData(Data)
		if not isstring(Data.RadiatorName) then
			Data.RadiatorName = Data.SizeId or Data.Id
		end
		local Class, Radiator

		if Data.BuildDupeInfo then
			Class = Data.ClassData
			
			Radiator = Radiators.GetItem(Class.ID, Data.ShortName)
		end
		
		if not Class then
			Data.RadiatorType = "Rad_B"

			Class = Radiators:GetEntries()[Data.RadiatorType]
			Radiator = Class.Lookup[Data.RadiatorName]
		end

		if not Data.RadiatorSize and Class.Scalable then
			Data.RadiatorSize = Radiator.Size
		end

		do -- External verifications
			if Class.VerifyData then
				Class.VerifyData(Data, Class)
			end

			HookRun("ACF_OnVerifyData", "acf_radiator", Data, Class)
		end
	end

	local function UpdateRadiator(Entity, Data, Class, Radiator)
		local Percent = Entity.Coolant / Entity.Capacity or 1
		local Material = Class.Material or Radiators and Radiators.Model

		Entity.ACF = Entity.ACF or {}
		Entity.ACF.Model = Radiator and Radiator.Model or Class.Model -- Must be set before changing model
		Entity.ClassData = Class

		Entity:SetScaledModel(Entity.ACF.Model)
		Entity:SetSize(Data.RadiatorSize)
		Entity:SetMaterial(Material or "")

		-- Storing all the relevant information on the entity for duping
		for _, V in ipairs(Entity.DataStore) do
			Entity[V] = Data[V]
		end

		local NameType = " " .. (Class.NameType or Radiator.Name)

		Entity.Name        	= Radiator.Name .. NameType
		Entity.ShortName   	= Radiator.Name
		Entity.EntType     	= Class.Name
		Entity.CoolantDensity = ACF.RadiatorCoolantDensity
		Entity.EmptyMass   	= 100 -- Total wall volume * cu in to cc * density of steel (kg/cc)
		Entity.NoLinks     	= Radiator and Radiator.Unlinkable or Class.Unlinkable
		Entity.Shape       	= Radiator and Radiator.Shape or Class.Shape
		Entity.Temperature 	= 25

		WireIO.SetupInputs(Entity, Inputs, Data, Class, Radiator, Radiator)
		WireIO.SetupOutputs(Entity, Outputs, Data, Class, Radiator, Radiator)

		Entity:SetNWString("WireName", "ACF " .. Entity.Name)

		Entity.Coolant = Percent*Entity.Capacity
		Entity.CoolantTemp = 25
		
		ACF.Activate(Entity, true)

		Entity:UpdateMass(true)
		
		WireLib.TriggerOutput(Entity, "Coolant", Entity.Coolant)
		WireLib.TriggerOutput(Entity, "Capacity", Entity.Capacity)
		WireLib.TriggerOutput(Entity, "Temperature", Entity.Temperature)
	end

	function MakeACF_Radiator(Player, Pos, Angle, Data)
		VerifyData(Data)
		local Radiator
		local Class = Classes.GetGroup(Radiators, Data.RadiatorType)
		if Data.BuildDupeInfo then
			Radiator = Data.ClassData.Lookup[Data.ShortName]
		else
			local Entries = Radiators.GetEntries()
			Radiator = Entries[Data.RadiatorType].Lookup[Data.RadiatorName]
		end


		local Limit    = Class.LimitConVar.Name
		local Model    = Class.Model or Radiator.Model
		local Material = Class.Material or Radiators and Radiators.Model

		if not Player:CheckLimit(Limit) then return end

		local CanSpawn = HookRun("ACF_PreSpawnEntity", "acf_radiator", Player, Data, Class, Radiator)

		if CanSpawn == false then return end

		local CurRadiator = ents.Create("acf_radiator")

		if not IsValid(CurRadiator) then return end

		CurRadiator.ACF		= CurRadiator.ACF or {}

		CurRadiator:SetScaledModel(Model)
		if Material then
			CurRadiator:SetMaterial(Material)
		end
		CurRadiator:SetAngles(Angle)
		CurRadiator:SetPos(Pos)
		CurRadiator:Spawn()

		Player:AddCleanup("acf_radiator", CurRadiator)
		Player:AddCount(Limit, CurRadiator)

		local Volume, Area
		local PhysObj = CurRadiator:GetPhysicsObject()
		
		Area = PhysObj:GetSurfaceArea()*2.54/1000
		Volume = PhysObj:GetVolume()/16.387064
		
		CurRadiator.Engines       	= {}
		CurRadiator.Leaking       	= 0
		CurRadiator.LastThink     	= 0
		CurRadiator.LastFuel      	= 0
		CurRadiator.LastActivated 	= 0
		CurRadiator.DataStore     	= Entities.GetArguments("acf_radiator")
		CurRadiator.Capacity 		= Volume/1000
		CurRadiator.Coolant			= CurRadiator.Capacity
		CurRadiator.SurfaceArea 	= Area
		CurRadiator.Volume		= Volume
		
		
		duplicator.ClearEntityModifier(CurRadiator, "mass")

		UpdateRadiator(CurRadiator, Data, Class, Radiator)

		
		if Class.OnSpawn then
			Class.OnSpawn(CurRadiator, Data, Class, Radiator)
		end

		HookRun("ACF_OnSpawnEntity", "acf_radiator", CurRadiator, Data, Class, Radiator)

		-- Fuel tanks should be active by default
		CurRadiator:TriggerInput("Active", 1)

		ActiveRadiators[CurRadiator] = true

		ACF.CheckLegal(CurRadiator)

		return CurRadiator
	end

	Entities.Register("acf_radiator", MakeACF_Radiator, "RadiatorType", "Size")

	ACF.RegisterLinkSource("acf_radiator", "Engines")

	------------------- Updating ---------------------

	function ENT:Update(Data)
		VerifyData(Data)
		
		local Class    = Classes.GetGroup(Radiators, Data.Radiator)
		local Radiator = Radiators.GetItem(Class.ID, Data.Radiator)
		local OldClass = self.ClassData
		local Feedback = ""

		local CanUpdate, Reason = HookRun("ACF_PreUpdateEntity", "acf_radiator", self, Data, Class, Radiator)

		if CanUpdate == false then return CanUpdate, Reason end

		if OldClass.OnLast then
			OldClass.OnLast(self, OldClass)
		end

		HookRun("ACF_OnEntityLast", "acf_radiator", self, OldClass)

		ACF.SaveEntity(self)

		UpdateRadiator(self, Data, Class, Radiator)

		ACF.RestoreEntity(self)

		if Class.OnUpdate then
			Class.OnUpdate(self, Data, Class, Radiator)
		end

		HookRun("ACF_OnUpdateEntity", "acf_radiator", self, Data, Class, Radiator)

		if next(self.Engines) then
			local Type    = self.Radiator
			local NoLinks = self.NoLinks
			local Count, Total = 0, 0

			for Engine in pairs(self.Engines) do
				if NoLinks then
					self:Unlink(Engine)

					Count = Count + 1
				end

				Total = Total + 1
			end

			if Count == Total then
				Feedback = "\nUnlinked from all engines due to radiator type or model change."
			elseif Count > 0 then
				local Text = "\nUnlinked from %s out of %s engines due to radiator type or model change."

				Feedback = Text:format(Count, Total)
			end
		end

		return true, "Radiator updated successfully!" .. Feedback
	end
end

--===============================================================================================--
-- Meta Funcs
--===============================================================================================--

function ENT:ACF_Activate(Recalc)
	local PhysObj = self:GetPhysicsObject()
	local Area    = PhysObj:GetSurfaceArea() * ACF.InchToCmSq
	local Armour  = self.EmptyMass * 1000 / Area / 0.78 * ACF.ArmorMod -- So we get the equivalent thickness of that prop in mm if all it's weight was a steel plate
	local Health  = Area / ACF.Threshold
	local Percent = 1

	if Recalc and self.ACF.Health and self.ACF.MaxHealth then
		Percent = self.ACF.Health / self.ACF.MaxHealth
	end

	self.ACF.Area      = Area
	self.ACF.Health    = Health * Percent
	self.ACF.MaxHealth = Health
	self.ACF.Armour    = Armour * (0.5 + Percent * 0.5)
	self.ACF.MaxArmour = Armour
	self.ACF.Type      = "Prop"
end

function ENT:ACF_OnDamage(DmgResult, DmgInfo)
	local HitRes    = Damage.doPropDamage(self, DmgResult, DmgInfo) -- Calling the standard prop damage function

	if HitRes.Kill then

		local Inflictor = DmgInfo:GetInflictor()

		if IsValid(Inflictor) and Inflictor:IsPlayer() then
			self.Inflictor = Inflictor
		end

		return HitRes
	end

	local Ratio = (HitRes.Damage / self.ACF.Health) ^ 0.75 -- Chance to explode from sheer damage, small shots = small chance
	local LeakChance = (1 - (self.Coolant / self.Capacity)) ^ 0.75 -- Chance to explode from fumes in tank, less fuel = more explodey

	-- It's gonna blow
	if math.random() < (LeakChance + Ratio) then
		self.Leaking = self.Leaking + self.Coolant * ((HitRes.Damage / self.ACF.Health) ^ 1.5) * 0.25

		WireLib.TriggerOutput(self, "Leaking", self.Leaking > 0 and 1 or 0)

		self:NextThink(Clock.CurTime + 0.1)
	end

	return HitRes
end

function ENT:Enable()
	WireLib.TriggerOutput(self, "Activated", self:CanConsume() and 1 or 0)
end

function ENT:Disable()
	WireLib.TriggerOutput(self, "Activated", 0)
end

do -- Mass Update
	local function UpdateMass(Entity, SelfTbl)
		SelfTbl = SelfTbl or Entity:GetTable()
		local Coolant    = SelfTbl.Liters or SelfTbl.Coolant
		local Mass    = math.floor(SelfTbl.EmptyMass + Coolant * SelfTbl.CoolantDensity)

		Contraption.SetMass(Entity, Mass)
	end

	function ENT:UpdateMass(Instant, SelfTbl)
		SelfTbl = SelfTbl or self:GetTable()
		if Instant then
			return UpdateMass(self, SelfTbl)
		end

		if TimerExists("ACF Mass Buffer" .. self:EntIndex()) then return end

		TimerCreate("ACF Mass Buffer" .. self:EntIndex(), 1, 1, function()
			if not IsValid(self) then return end

			UpdateMass(self, SelfTbl)
		end)
	end
end

do -- Overlay Update
	local Classes = ACF.Classes
	local Radiators = Classes.Radiators

	local Text = "%s\n\n%sRadiator Type: %s\n%s"

	function ENT:UpdateOverlayText()
		local Size = ""
		local Status, Content

		if self.Leaking > 0 then
			Status = "Leaking"
		else
			Status = self:CanConsume() and "Providing Coolant\n" or "Idle"
		end
		
		local Class = self.ClassData
		
		local RadiatorTypeID = Class.ID
		local RadiatorType = Radiators.Get(RadiatorTypeID)
		local Coolant = self.Coolant
		local Size = self.Name
		if RadiatorType and RadiatorType.RadiatorOverlayText then
			Content = RadiatorType.RadiatorOverlayText(Coolant)
		else
			local Liters = Round(Coolant, 2)
			local Gallons = Round(Coolant * ACF.LToGal, 2)

			Content = "Coolant Remaining: " .. Liters .. " liters / " .. Gallons .. " gallons"
		end
		return Text:format(Size, Status, RadiatorTypeID, Content)
	end
end

ACF.AddInputAction("acf_radiator", "Active", function(Entity, Value)
	Entity.Active = tobool(Value)

	WireLib.TriggerOutput(Entity, "Activated", Entity:CanConsume() and 1 or 0)
end)

ACF.AddInputAction("acf_radiator", "Coolant Tank", function(Entity, Value)
	Entity.SupplyCoolant = tobool(Value) or nil
end)

function ENT:CanConsume(SelfTbl)
	SelfTbl = SelfTbl or self:GetTable()
	if SelfTbl.Disabled then return false end
	if not SelfTbl.Active then return false end

	return SelfTbl.Coolant > 0
end

function ENT:Consume(Amount, SelfTbl)
	SelfTbl = SelfTbl or self:GetTable()
	local Coolant = Clamp(SelfTbl.Coolant - Amount, 0, SelfTbl.Capacity)
	SelfTbl.Coolant = Coolant

	Coolant = Round(Coolant, 2)
	local Activated = self:CanConsume(SelfTbl) and 1 or 0

	if SelfTbl.LastActivated ~= Activated then
		SelfTbl.LastActivated = Activated
		WireLib.TriggerOutput(self, "Activated", Activated)

		self:UpdateOverlay()
	end
end

function Dissipation(self, SelfTbl, DeltaTime, EngineOn)
		local Temperature = SelfTbl.Temperature
		WireLib.TriggerOutput(self, "Temperature", Round(Temperature,3))
		local AirSpeed = 0.1
		
		if Temperature>=50 and EngineOn then
			AirSpeed = 4
		end
		local AirCoeff = 10*(self:GetPhysicsObject():GetVelocity():Length()+AirSpeed)^0.8
		local PowR = (AirCoeff*(SelfTbl.SurfaceArea/4))/SelfTbl.EmptyMass*0.9*DeltaTime
	
		local deltaFromConvection = Round((25-Temperature)*PowR,3)
		local deltaFromRadiation  = Round(SelfTbl.SurfaceArea/4*5.67*10^-8*(25^4-Temperature^4)*DeltaTime,3)
		Temperature = Round(Temperature+deltaFromConvection+deltaFromRadiation,3)
		SelfTbl.Temperature = Clamp(Temperature,25,212)
		if Temperature >=100 then
			SelfTbl.Coolant = SelfTbl.Coolant*0.999
			WireLib.TriggerOutput(self, "Coolant", SelfTbl.Coolant)
		end
		--print("Rad Temp "..SelfTbl.Temperature.." Coolant temp "..SelfTbl.CoolantTemp.." Temp Delta "..deltaFromConvection.." cv, "..deltaFromRadiation.." r")
end

local TickInterval = engine.TickInterval

function ENT:IntakeCoolant(Amount, TempIn, SelfTbl, DeltaTime, EngineOn)
	local Temperature = SelfTbl.Temperature
	local CoolantTemp = TempIn
	local Coolant = SelfTbl.Coolant
	local Capacity = SelfTbl.Capacity
	local PercentFull = Coolant/Capacity
	--local deltaTemp = ((0.2*SelfTbl.SurfaceArea/3)*(TempIn - Temperature))/(SelfTbl.EmptyMass*0.9)--0.2 kW/k, 0.9 J/Kg*K
	if PercentFull >= 0.05 then
		local deltaTempFromCoolant = (0.6*SelfTbl.SurfaceArea/4*(TempIn - 25))/(SelfTbl.EmptyMass*0.9)
		Temperature = Temperature+deltaTempFromCoolant
		SelfTbl.Temperature = Clamp(Temperature,25,212)
	
		local CoolantDelta = ((0.05*SelfTbl.SurfaceArea/4*(TempIn - Temperature))/(Amount*1.045*3.14))*DeltaTime
		CoolantTemp = CoolantTemp+CoolantDelta
		SelfTbl.CoolantTemp = CoolantTemp
		--print("Coolant Heated Radiator: "..deltaTempFromCoolant.." Coolant Delta "..CoolantDelta)
		Dissipation(self, SelfTbl, DeltaTime, EngineOn)
		return CoolantTemp
	else
		local deltaTempFromCoolant = (1*SelfTbl.SurfaceArea/4*(TempIn - 25))/(SelfTbl.EmptyMass*0.9)*Amount
		Temperature = Temperature+deltaTempFromCoolant
		SelfTbl.Temperature = Clamp(Temperature,25,212)
		Dissipation(self, SelfTbl, DeltaTime, EngineOn)
		return SelfTbl.CoolantTemp
	end
end

do
	local function RefillRadiator(Entity)
		net.Start("ACF_RefillRadiator")
			net.WriteEntity(Entity)
		net.Broadcast()
	end

	local function StopRefillRadiator(Entity)
		net.Start("ACF_StopRefillRadiator")
			net.WriteEntity(Entity)
		net.Broadcast()
	end

	function ENT:Think()
		self:NextThink(Clock.CurTime + 1)

		local Leaking = self.Leaking

		if Leaking > 0 then
			self:Consume(Leaking)

			local coolant = self.Coolant
			Leaking = Clamp(Leaking - (1 / math.max(Coolant, 1)) ^ 0.5, 0, Fuel) -- Radiators are self healing
			self.Leaking = Leaking

			WireLib.TriggerOutput(self, "Leaking", Leaking > 0 and 1 or 0)

			self:NextThink(Clock.CurTime + 0.25)
		end

		if self.Refilling then
			StopRefillRadiator(self)
			self.Refilling = false
		end

		-- Refuelling
		if self.SupplyCoolant and self:CanConsume() then
			local DeltaTime = Clock.CurTime - self.LastThink
			local Position  = self:GetPos()

			for CurRadiator in pairs(ACF.Radiators) do
				local Distance = Position:DistToSqr(CurRadiator:GetPos())

				if CanRefuel(self, CurRadiator, Distance) then
					local Exchange  = math.min(DeltaTime * ACF.RefuelSpeed * ACF.FuelRate, self.Coolant, CurRadiator.Capacity - CurRadiator.Fuel)
					local CanRefill = hook.Run("ACF_PreRefillFuel", self, CurRadiator, Exchange)

					if not CanRefill then continue end

					self:Consume(Exchange)
					CurRadiator:Consume(-Exchange)

					if self.RadiatorType == "standard" then
						Sounds.SendSound(self, "vehicles/jetski/jetski_no_gas_start.wav", 70, 120, 0.5)
						Sounds.SendSound(Tank, "vehicles/jetski/jetski_no_gas_start.wav", 70, 120, 0.5)
					end

					RefillRadiator(self)
					self.Refilling = true
				end
			end
		end

		self.LastThink = Clock.CurTime

		return true
	end
end

function ENT:OnRemove()
	local Class = self.ClassData

	if Class.OnLast then
		Class.OnLast(self, Class)
	end

	HookRun("ACF_OnEntityLast", "acf_radiator", self, Class)

	for Engine in pairs(self.Engines) do
		self:Unlink(Engine)
	end

	ActiveRadiators[self] = nil

	WireLib.Remove(self)
end

function ENT:OnResized(Size)
	do -- Calculate new empty mass
		local Wall = ACF.RadiatorArmor * ACF.MmToInch -- Wall thickness in inches
		local Class = self.ClassData
		local _, Area

		if Class.CalcVolume then
			_, Area = Class.CalcVolume(Size, Wall)
		else -- Default to finding surface area/volume based off physics object instead
			local PhysObj = self:GetPhysicsObject()
			Area = PhysObj:GetSurfaceArea()*2.54/1000
		end

		local Mass = (Area * Wall) * ACF.InchToCmCu * ACF.SteelDensity -- Total wall volume * cu in to cc * density of steel (kg/cc)

		self.EmptyMass = Mass
	end

	self.HitBoxes = {
		Main = {
			Pos = self:OBBCenter(),
			Scale = Size,
		}
	}
end