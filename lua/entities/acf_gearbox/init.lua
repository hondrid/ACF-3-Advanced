DEFINE_BASECLASS("acf_base_simple") -- Required to get the local BaseClass

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

-- Local variables ---------------------------------

local ACF         = ACF
local Contraption = ACF.Contraption
local Mobility	  = ACF.Mobility
local MobilityObj = Mobility.Objects
local Utilities   = ACF.Utilities
local Clock       = Utilities.Clock
local Clamp       = math.Clamp
local abs         = math.abs
local min         = math.min
local max         = math.max
local MaxDistance = ACF.MobilityLinkDistance * ACF.MobilityLinkDistance

local function CalcWheel(Entity, Link, Wheel, SelfWorld)
	local WheelPhys = Wheel:GetPhysicsObject()
	local VelDiff = WheelPhys:LocalToWorldVector(WheelPhys:GetAngleVelocity()) - SelfWorld
	local BaseRPM = VelDiff:Dot(WheelPhys:LocalToWorldVector(Link.Axis))
	local GearRatio = Entity.GearRatio

	Link.Vel = BaseRPM

	if GearRatio == 0 then return 0 end

	-- Reported BaseRPM is in angle per second and in the wrong direction, so we convert and add the gearratio
	return BaseRPM / GearRatio / -6
end

do -- Spawn and Update functions -----------------------
	local Classes   = ACF.Classes
	local WireIO    = Utilities.WireIO
	local Gearboxes = Classes.Gearboxes
	local Entities  = Classes.Entities

	local Inputs = {
		"Gear (Changes the current gear to the given value.)",
		"Gear Up (Attempts to shift up the current gear.)",
		"Gear Down (Attempts to shift down the current gear.)",
	}
	local Outputs = {
		"Current Gear (Returns the gear currently in use.)",
		"Ratio (Returns the current gear ratio, based on the current gear and final drive.)",
		"Entity (The gearbox itself.) [ENTITY]"
	}

	local function VerifyData(Data)
		if not Data.Gearbox then
			Data.Gearbox = Data.Id or "2Gear-T-S"
		end

		local Class = Classes.GetGroup(Gearboxes, Data.Gearbox)

		if not Class then
			Data.Gearbox = "2Gear-T-S"

			Class = Classes.GetGroup(Gearboxes, "2Gear-T-S")
		end

		do -- Gears table verification
			local Gears = Data.Gears

			if not istable(Gears) then
				Gears = { [0] = 0 }

				Data.Gears = Gears
			else
				Gears[0] = 0
			end

			for I = 1, Class.Gears.Max do
				local Gear = ACF.CheckNumber(Gears[I])

				if not Gear then
					Gear = ACF.CheckNumber(Data["Gear" .. I], I * 0.1)

					Data["Gear" .. I] = nil
				end

				Gears[I] = Clamp(Gear, -1, 1)
			end
		end

		do -- Final drive verification
			local Final = ACF.CheckNumber(Data.FinalDrive)

			if not Final then
				Final = ACF.CheckNumber(Data.Gear0, 1)

				Data.Gear0 = nil
			end

			Data.FinalDrive = Clamp(Final, -1, 1)
		end

		do -- External verifications
			if Class.VerifyData then
				Class.VerifyData(Data, Class)
			end

			hook.Run("ACF_OnVerifyData", "acf_gearbox", Data, Class)
		end
	end

	local function UpdateGearbox(Entity, Data, Class, Gearbox)
		local Mass = Gearbox.Mass

		Entity.ACF = Entity.ACF or {}

		Contraption.SetModel(Entity, Gearbox.Model)

		Entity:PhysicsInit(SOLID_VPHYSICS)
		Entity:SetMoveType(MOVETYPE_VPHYSICS)

		-- Storing all the relevant information on the entity for duping
		for _, V in ipairs(Entity.DataStore) do
			Entity[V] = Data[V]
		end

		Entity.Name         = Gearbox.Name
		Entity.ShortName    = Gearbox.ID
		Entity.EntType      = Class.Name
		Entity.ClassData    = Class
		Entity.DefaultSound = Class.Sound
		Entity.SwitchTime   = Gearbox.Switch
		Entity.MaxTorque    = Gearbox.MaxTorque
		Entity.MinGear      = Class.Gears.Min
		Entity.MaxGear      = Class.Gears.Max
		Entity.GearCount    = Entity.MaxGear
		Entity.DualClutch   = Gearbox.DualClutch
		Entity.In           = Entity:WorldToLocal(Entity:GetAttachment(Entity:LookupAttachment("input")).Pos)
		Entity.OutL         = Entity:WorldToLocal(Entity:GetAttachment(Entity:LookupAttachment("driveshaftL")).Pos)
		Entity.OutR         = Entity:WorldToLocal(Entity:GetAttachment(Entity:LookupAttachment("driveshaftR")).Pos)
		Entity.HitBoxes     = ACF.GetHitboxes(Gearbox.Model)

		WireIO.SetupInputs(Entity, Inputs, Data, Class, Gearbox)
		WireIO.SetupOutputs(Entity, Outputs, Data, Class, Gearbox)

		Entity:SetNWString("WireName", "ACF " .. Entity.Name)

		ACF.Activate(Entity, true)

		Contraption.SetMass(Entity, Mass)

		Entity:ChangeGear(1)

		-- ChangeGear doesn't update GearRatio if the gearbox is already in gear 1
		Entity.GearRatio = Entity.Gears[1] * Entity.FinalDrive
	end

	local function CheckRopes(Entity, Target)
		local Ropes = Entity[Target]

		if not next(Ropes) then return end

		for Ent, Link in pairs(Ropes) do
			local OutPos = Entity:LocalToWorld(Link:GetOrigin())
			local InPos = Ent.In and Ent:LocalToWorld(Ent.In) or Ent:GetPos()

			-- make sure it is not stretched too far
			if OutPos:Distance(InPos) > Link.RopeLen * 1.5 then
				Entity:Unlink(Ent)
				continue
			end

			-- make sure the angle is not excessive
			local DrvAngle = (OutPos - InPos):GetNormalized():Dot((Entity:GetRight() * Link:GetOrigin().y):GetNormalized())

			if DrvAngle < 0.7 then
				Entity:Unlink(Ent)
			end
		end
	end

	-- Some information may still be passed from the menu tool
	-- We don't want to save it on the entity if it's not needed
	local function CleanupData(Class, Gearbox)
		if Class ~= "acf_gearbox" then return end

		if not Gearbox.Automatic then
			Gearbox.Reverse = nil
		end

		if not Gearbox.CVT then
			Gearbox.MinRPM = nil
			Gearbox.MaxRPM = nil
		end

		if Gearbox.DualClutch then
			Gearbox:SetBodygroup(1, 1)
		end
	end

	hook.Add("ACF_OnSpawnEntity", "ACF Cleanup Gearbox Data", CleanupData)
	hook.Add("ACF_OnUpdateEntity", "ACF Cleanup Gearbox Data", CleanupData)
	hook.Add("ACF_OnSetupInputs", "ACF Cleanup Gearbox Data", function(Entity, List)
		if Entity:GetClass() ~= "acf_gearbox" then return end

		local Count = #List

		if Entity.DualClutch then
			List[Count + 1] = "Left Clutch (Sets the percentage of power, from 0 to 1, that will not be passed to the left side output.)"
			List[Count + 2] = "Right Clutch (Sets the percentage of power, from 0 to 1, that will not be passed to the right side output.)"
			List[Count + 3] = "Left Brake (Sets the amount of power given to the left side brakes.)"
			List[Count + 4] = "Right Brake (Sets the amount of power given to the right side brakes.)"
		else
			List[Count + 1] = "Clutch (Sets the percentage of power, from 0 to 1, that will not be passed to the output.)"
			List[Count + 2] = "Brake (Sets the amount of power given to the brakes.)"
		end
	end)
	hook.Add("ACF_OnEntityLast", "ACF Cleanup Gearbox Data", function(Class, Gearbox)
		if Class ~= "acf_gearbox" then return end

		Gearbox:SetBodygroup(1, 0)
	end)

	-------------------------------------------------------------------------------

	function MakeACF_Gearbox(Player, Pos, Angle, Data)
		VerifyData(Data)

		local Class   = Classes.GetGroup(Gearboxes, Data.Gearbox)
		local Gearbox = Gearboxes.GetItem(Class.ID, Data.Gearbox)
		local Limit   = Class.LimitConVar.Name

		if not Player:CheckLimit(Limit) then return end

		local CanSpawn = hook.Run("ACF_PreSpawnEntity", "acf_gearbox", Player, Data, Class, Gearbox)

		if CanSpawn == false then return false end

		local Entity = ents.Create("acf_gearbox")

		if not IsValid(Entity) then return end

		Entity:SetAngles(Angle)
		Entity:SetPos(Pos)
		Entity:Spawn()

		Player:AddCleanup("acf_gearbox", Entity)
		Player:AddCount(Limit, Entity)

		Entity.SoundPath      = Class.Sound
		Entity.Engines        = {}
		Entity.Wheels         = {} -- a "Link" has these components: Ent, Side, Axis, Rope, RopeLen, Output, ReqTq, Vel
		Entity.GearboxIn      = {}
		Entity.GearboxOut     = {}
		Entity.TotalReqTq     = 0
		Entity.TorqueOutput   = 0
		Entity.LBrake         = 0
		Entity.RBrake         = 0
		Entity.ChangeFinished = 0
		Entity.InGear         = false
		Entity.Braking        = false
		Entity.LastBrake      = 0
		Entity.LastActive     = 0
		Entity.LClutch        = 1
		Entity.RClutch        = 1
		Entity.DataStore      = Entities.GetArguments("acf_gearbox")

		duplicator.ClearEntityModifier(Entity, "mass")

		UpdateGearbox(Entity, Data, Class, Gearbox)

		if Class.OnSpawn then
			Class.OnSpawn(Entity, Data, Class, Gearbox)
		end

		hook.Run("ACF_OnSpawnEntity", "acf_gearbox", Entity, Data, Class, Gearbox)

		ACF.CheckLegal(Entity)

		timer.Create("ACF Gearbox Clock " .. Entity:EntIndex(), 3, 0, function()
			if IsValid(Entity) then
				CheckRopes(Entity, "GearboxOut")
				CheckRopes(Entity, "Wheels")
			else
				timer.Remove("ACF Gearbox Clock " .. Entity:EntIndex())
			end
		end)

		return Entity
	end

	Entities.Register("acf_gearbox", MakeACF_Gearbox, "Gearbox", "Gears", "FinalDrive", "ShiftPoints", "Reverse", "MinRPM", "MaxRPM")

	ACF.RegisterLinkSource("acf_gearbox", "GearboxIn")
	ACF.RegisterLinkSource("acf_gearbox", "GearboxOut")
	ACF.RegisterLinkSource("acf_gearbox", "Engines")
	ACF.RegisterLinkSource("acf_gearbox", "Wheels")

	------------------- Updating ---------------------

	function ENT:Update(Data)
		VerifyData(Data)

		local Class    = Classes.GetGroup(Gearboxes, Data.Gearbox)
		local Gearbox  = Class.Lookup[Data.Gearbox]
		local OldClass = self.ClassData
		local Feedback = ""

		local CanUpdate, Reason = hook.Run("ACF_PreUpdateEntity", "acf_gearbox", self, Data, Class, Gearbox)
		if CanUpdate == false then return CanUpdate, Reason end

		if OldClass.OnLast then
			OldClass.OnLast(self, OldClass)
		end

		hook.Run("ACF_OnEntityLast", "acf_gearbox", self, OldClass)

		ACF.SaveEntity(self)

		UpdateGearbox(self, Data, Class, Gearbox)

		ACF.RestoreEntity(self)

		if Class.OnUpdate then
			Class.OnUpdate(self, Data, Class, Gearbox)
		end

		hook.Run("ACF_OnUpdateEntity", "acf_gearbox", self, Data, Class, Gearbox)

		if next(self.Engines) then
			local Count, Total = 0, 0

			for Engine in pairs(self.Engines) do
				self:Unlink(Engine)

				local Result = self:Link(Engine)

				if not Result then Count = Count + 1 end

				Total = Total + 1
			end

			if Count == Total then
				Feedback = Feedback .. "\nUnlinked all engines due to excessive driveshaft angle."
			elseif Count > 0 then
				local Text = Feedback .. "\nUnlinked %s out of %s engines due to excessive driveshaft angle."

				Feedback = Text:format(Count, Total)
			end
		end

		if next(self.Wheels) then
			local Count, Total = 0, 0

			for Wheel in pairs(self.Wheels) do
				self:Unlink(Wheel)

				local Result = self:Link(Wheel)

				if not Result then Count = Count + 1 end

				Total = Total + 1
			end

			if Count == Total then
				Feedback = Feedback .. "\nUnlinked all wheels due to excessive driveshaft angle."
			elseif Count > 0 then
				local Text = Feedback .. "\nUnlinked %s out of %s wheels due to excessive driveshaft angle."

				Feedback = Text:format(Count, Total)
			end
		end

		if next(self.GearboxIn) or next(self.GearboxOut) then
			local Count, Total = 0, 0

			for Entity in pairs(self.GearboxIn) do
				Entity:Unlink(self)

				local Result = Entity:Link(self)

				if not Result then Count = Count + 1 end

				Total = Total + 1
			end

			for Entity in pairs(self.GearboxOut) do
				self:Unlink(Entity)

				local Result = self:Link(Entity)

				if not Result then Count = Count + 1 end

				Total = Total + 1
			end

			if Count == Total then
				Feedback = Feedback .. "\nUnlinked all gearboxes due to excessive driveshaft angle."
			elseif Count > 0 then
				local Text = Feedback .. "\nUnlinked %s out of %s gearboxes due to excessive driveshaft angle."

				Feedback = Text:format(Count, Total)
			end
		end

		return true, "Gearbox updated successfully!" .. Feedback
	end
end ----------------------------------------------------

do -- Inputs -------------------------------------------
	local function SetCanApplyBrakes(Gearbox)
		local CanApply = Gearbox.LBrake ~= 0 or Gearbox.RBrake ~= 0

		if CanApply ~= Gearbox.Braking then
			Gearbox.Braking = CanApply

		end
	end

	ACF.AddInputAction("acf_gearbox", "Gear", function(Entity, Value)
		if Entity.Automatic then
			Entity:ChangeDrive(Value)
		else
			Entity:ChangeGear(Value)
		end
	end)

	ACF.AddInputAction("acf_gearbox", "Gear Up", function(Entity, Value)
		if not tobool(Value) then return end

		if Entity.Automatic then
			Entity:ChangeDrive(Entity.Drive + 1)
		else
			Entity:ChangeGear(Entity.Gear + 1)
		end
	end)

	ACF.AddInputAction("acf_gearbox", "Gear Down", function(Entity, Value)
		if not tobool(Value) then return end

		if Entity.Automatic then
			Entity:ChangeDrive(Entity.Drive - 1)
		else
			Entity:ChangeGear(Entity.Gear - 1)
		end
	end)

	ACF.AddInputAction("acf_gearbox", "Clutch", function(Entity, Value)
		Entity.LClutch = Clamp(1 - Value, 0, 1)
		Entity.RClutch = Clamp(1 - Value, 0, 1)
	end)

	ACF.AddInputAction("acf_gearbox", "Left Clutch", function(Entity, Value)
		if not Entity.DualClutch then return end

		Entity.LClutch = Clamp(1 - Value, 0, 1)
	end)

	ACF.AddInputAction("acf_gearbox", "Right Clutch", function(Entity, Value)
		if not Entity.DualClutch then return end

		Entity.RClutch = Clamp(1 - Value, 0, 1)
	end)

	ACF.AddInputAction("acf_gearbox", "Brake", function(Entity, Value)
		Entity.LBrake = Clamp(Value, 0, 10000)
		Entity.RBrake = Clamp(Value, 0, 10000)
	end)

	ACF.AddInputAction("acf_gearbox", "Left Brake", function(Entity, Value)
		if not Entity.DualClutch then return end

		Entity.LBrake = Clamp(Value, 0, 10000)
	end)

	ACF.AddInputAction("acf_gearbox", "Right Brake", function(Entity, Value)
		if not Entity.DualClutch then return end

		Entity.RBrake = Clamp(Value, 0, 10000)
	end)

	ACF.AddInputAction("acf_gearbox", "CVT Ratio", function(Entity, Value)
		if not Entity.CVT then return end

		Entity.CVTRatio = Clamp(Value, 0, 1)
	end)

	ACF.AddInputAction("acf_gearbox", "Steer Rate", function(Entity, Value)
		if not Entity.DoubleDiff then return end

		Entity.SteerRate = Clamp(Value, -1, 1)
	end)

	ACF.AddInputAction("acf_gearbox", "Hold Gear", function(Entity, Value)
		if not Entity.Automatic then return end

		Entity.Hold = tobool(Value)
	end)

	ACF.AddInputAction("acf_gearbox", "Shift Speed Scale", function(Entity, Value)
		if not Entity.Automatic then return end

		Entity.ShiftScale = Clamp(Value, 0.1, 1.5)
	end)
end ----------------------------------------------------

do -- Linking ------------------------------------------
	local function CheckLoopedGearbox(This, Target)
		local Queued = { [Target] = true }
		local Checked = {}
		local Entity

		while next(Queued) do
			Entity = next(Queued)

			if Entity == This then
				return true
			end

			Checked[Entity] = true
			Queued[Entity]  = nil

			for Gearbox in pairs(Entity.GearboxOut) do
				if not Checked[Gearbox] then
					Queued[Gearbox] = true
				end
			end
		end

		return false
	end

	local function GenerateLinkTable(Entity, Target)
		local InPos = Target.In or Vector()
		local InPosWorld = Target:LocalToWorld(InPos)
		local OutPos, Side

		if Entity:WorldToLocal(InPosWorld).y < 0 then
			OutPos = Entity.OutL
			Side = 0
		else
			OutPos = Entity.OutR
			Side = 1
		end

		local OutPosWorld = Entity:LocalToWorld(OutPos)
		local DrvAngle = (OutPosWorld - InPosWorld):GetNormalized():Dot((Entity:GetRight() * OutPos.y):GetNormalized())

		if DrvAngle < 0.7 then return end

		local Rope

		if Entity.Owner:GetInfoNum("ACF_MobilityRopeLinks", 1) ~= 0 then
			Rope = constraint.CreateKeyframeRope(OutPosWorld, 1, "cable/cable2", nil, Entity, OutPos, 0, Target, InPos, 0)
		end

		local Phys = Target:GetPhysicsObject()
		local Axis = Phys:WorldToLocalVector(Entity:GetRight())

		local Link	= MobilityObj.Link(Entity, Target)
		Link:SetOrigin(OutPos)
		Link:SetTargetPos(InPos)
		Link:SetAxis(Axis)
		Link.Side = Side
		Link.Rope = Rope
		Link.RopeLen = (OutPosWorld - InPosWorld):Length()

		return Link
	end

	local function LinkWheel(Gearbox, Wheel)
		if Gearbox.Wheels[Wheel] then return false, "This wheel is already linked to this gearbox!" end
		if Gearbox:GetPos():DistToSqr(Wheel:GetPos()) > MaxDistance then return false, "This wheel is too far away from this gearbox!" end

		local Link = GenerateLinkTable(Gearbox, Wheel)

		if not Link then return false, "Cannot link due to excessive driveshaft angle!" end

		Link.LastVel   = 0

		Gearbox.Wheels[Wheel] = Link

		Wheel:CallOnRemove("ACF_GearboxUnlink" .. Gearbox:EntIndex(), function()
			if IsValid(Gearbox) then
				Gearbox:Unlink(Wheel)
			end
		end)

		Gearbox:InvalidateClientInfo()

		return true, "Wheel linked successfully!"
	end

	local function LinkGearbox(Gearbox, Target)
		if Gearbox.GearboxOut[Target] then return false, "These gearboxes are already linked to each other!" end
		if Target.GearboxIn[Gearbox] then return false, "These gearboxes are already linked to each other!" end
		if Gearbox:GetPos():DistToSqr(Target:GetPos()) > MaxDistance then return false, "These gearboxes are too far away from each other!" end
		if CheckLoopedGearbox(Gearbox, Target) then return false, "You cannot link gearboxes in a loop!" end

		local Link = GenerateLinkTable(Gearbox, Target)

		if not Link then return false, "Cannot link due to excessive driveshaft angle!" end

		Gearbox.GearboxOut[Target] = Link
		Target.GearboxIn[Gearbox]  = true

		Gearbox:InvalidateClientInfo()

		return true, "Gearbox linked successfully!"
	end

	ACF.RegisterClassLink("acf_gearbox", "prop_physics", LinkWheel)
	ACF.RegisterClassLink("acf_gearbox", "acf_gearbox", LinkGearbox)
	ACF.RegisterClassLink("acf_gearbox", "tire", LinkWheel)
end ----------------------------------------------------

do -- Unlinking ----------------------------------------
	local function UnlinkWheel(Gearbox, Wheel)
		if Gearbox.Wheels[Wheel] then
			local Link = Gearbox.Wheels[Wheel]

			if IsValid(Link.Rope) then
				Link.Rope:Remove()
			end

			Gearbox.Wheels[Wheel] = nil

			Wheel:RemoveCallOnRemove("ACF_GearboxUnlink" .. Gearbox:EntIndex())

			Gearbox:InvalidateClientInfo()

			return true, "Wheel unlinked successfully!"
		end

		return false, "This wheel is not linked to this gearbox!"
	end

	local function UnlinkGearbox(Gearbox, Target)
		local GearboxToTarget = Gearbox.GearboxOut[Target] or Target.GearboxIn[Gearbox]
		local TargetToGearbox = Target.GearboxOut[Gearbox] or Gearbox.GearboxIn[Target]

		if GearboxToTarget or TargetToGearbox then
			local Link = Gearbox.GearboxOut[Target] or Target.GearboxOut[Gearbox]

			if IsValid(Link.Rope) then
				Link.Rope:Remove()
			end

			Gearbox.GearboxIn[Target]  = nil
			Gearbox.GearboxOut[Target] = nil
			Target.GearboxIn[Gearbox]  = nil
			Target.GearboxOut[Gearbox] = nil

			Gearbox:InvalidateClientInfo()

			return true, "Gearbox unlinked successfully!"
		end

		return false, "These gearboxes are not linked to each other!"
	end

	ACF.RegisterClassUnlink("acf_gearbox", "prop_physics", UnlinkWheel)
	ACF.RegisterClassUnlink("acf_gearbox", "acf_gearbox", UnlinkGearbox)
	ACF.RegisterClassUnlink("acf_gearbox", "tire", UnlinkWheel)
end ----------------------------------------------------

do -- Overlay Text -------------------------------------
	local Text = "%s\nCurrent Gear: %s\n\n%s\nFinal Drive: %s\nTorque Rating: %s Nm / %s fl-lb\nTorque Output: %s Nm / %s fl-lb"

	function ENT:UpdateOverlayText()
		local GearsText = self.ClassData.GetGearsText and self.ClassData.GetGearsText(self)
		local Final     = math.Round(self.FinalDrive, 2)
		local Torque    = math.Round(self.MaxTorque * 0.73)
		local Output    = math.Round(self.TorqueOutput * 0.73)

		if not GearsText or GearsText == "" then
			local Gears = self.Gears

			GearsText = ""

			for I = 1, self.MaxGear do
				GearsText = GearsText .. "Gear " .. I .. ": " .. math.Round(Gears[I], 2) .. "\n"
			end
		end

		return Text:format(self.Name, self.Gear, GearsText, Final, self.MaxTorque, Torque, math.floor(self.TorqueOutput), Output)
	end
end ----------------------------------------------------

do -- Gear Shifting ------------------------------------
	local Sounds = Utilities.Sounds

	-- Handles gearing for automatic gearboxes. 0 = Neutral, 1 = Drive, 2 = Reverse
	function ENT:ChangeDrive(Value)
		Value = Clamp(math.floor(Value), 0, 2)

		if self.Drive == Value then return end

		self.Drive = Value

		self:ChangeGear(Value == 2 and self.GearCount or Value)
	end

	function ENT:ChangeGear(Value)
		Value = Clamp(math.floor(Value), self.MinGear, self.GearCount)

		if self.Gear == Value then return end

		self.Gear           = Value
		self.InGear         = false
		self.GearRatio      = self.Gears[Value] * self.FinalDrive
		self.ChangeFinished = Clock.CurTime + self.SwitchTime

		local SoundPath  = self.SoundPath

		if SoundPath ~= "" then
			local Pitch = self.SoundPitch and math.Clamp(self.SoundPitch * 100, 0, 255) or 100
			local Volume = self.SoundVolume or 0.5

			Sounds.SendSound(self, SoundPath, 70, Pitch, Volume)
		end

		WireLib.TriggerOutput(self, "Current Gear", Value)
		WireLib.TriggerOutput(self, "Ratio", self.GearRatio)
	end
end ----------------------------------------------------

do -- Movement -----------------------------------------
	local deg         = math.deg
	local function ActWheel(Link, Wheel, Torque, DeltaTime, Brake)
		
		local Phys = Wheel:GetPhysicsObject()
	
		if not Phys:IsMotionEnabled() then return end -- skipping entirely if its frozen

		local TorqueAxis = Phys:LocalToWorldVector(Link.Axis)
		local Mass = Contraption.TotalMass
		local BrakeRatio = Brake/100 
		local IBR = 1-BrakeRatio--inverse ratio to "force clutch" on forward torque
		local TorqueAxis = Phys:LocalToWorldVector(Link.Axis)
		local ForwardTorque =  math.deg( -Torque * 1.5 * IBR)
		
		local WheelInertia = Phys:GetInertia()
		local WheelAngVel = Phys:LocalToWorldVector(Phys:GetAngleVelocity())
		local Stabilizer =  math.abs((WheelInertia*WheelAngVel):Dot(TorqueAxis))
		local BrakeTorque = BrakeRatio  * -Stabilizer * (Mass/1000)--Mass Multiplier to help heavy vehicles brake
		local TorqueMult = Clamp(ForwardTorque+BrakeTorque,-50000,50000)

		Phys:ApplyTorqueCenter(TorqueAxis * TorqueMult * DeltaTime)
		
	end

	function ENT:Calc(InputRPM, InputInertia)
		local SelfTbl = self:GetTable()
		if SelfTbl.LastActive == Clock.CurTime then return SelfTbl.TorqueOutput end

		if SelfTbl.ChangeFinished < Clock.CurTime then
			SelfTbl.InGear = true
		end

		local BoxPhys = self:GetAncestor():GetPhysicsObject()
		local SelfWorld = BoxPhys:LocalToWorldVector(BoxPhys:GetAngleVelocity())
		local Gear = SelfTbl.Gear

		if SelfTbl.CVT and Gear == 1 then
			local Gears = SelfTbl.Gears

			if SelfTbl.CVTRatio > 0 then
				Gears[1] = Clamp(SelfTbl.CVTRatio, 0.01, 1)
			else
				local MinRPM  = SelfTbl.MinRPM
				Gears[1] = Clamp((InputRPM - MinRPM) / (SelfTbl.MaxRPM - MinRPM), 0.05, 1)
			end

			local GearRatio = Gears[1] * SelfTbl.FinalDrive
			SelfTbl.GearRatio = GearRatio

			if SelfTbl.LastRatio ~= GearRatio then
				SelfTbl.LastRatio = GearRatio
				WireLib.TriggerOutput(self, "Ratio", GearRatio)
			end
		end

		if SelfTbl.Automatic and SelfTbl.Drive == 1 and SelfTbl.InGear then
			local PhysVel = BoxPhys:GetVelocity():Length()

			if not SelfTbl.Hold and Gear ~= SelfTbl.MaxGear and PhysVel > (SelfTbl.ShiftPoints[Gear] * SelfTbl.ShiftScale) then
				self:ChangeGear(Gear + 1)
			elseif PhysVel < (SelfTbl.ShiftPoints[Gear - 1] * SelfTbl.ShiftScale) then
				self:ChangeGear(Gear - 1)
			end
		end

		local TorqueOutput = 0
		local TotalReqTq = 0
		local LClutch = SelfTbl.LClutch
		local RClutch = SelfTbl.RClutch
		local GearRatio = SelfTbl.GearRatio

		if GearRatio == 0 then return 0 end

		for Ent, Link in pairs(SelfTbl.GearboxOut) do
			local Clutch = Link.Side == 0 and LClutch or RClutch

			Link.ReqTq = 0

			if not Ent.Disabled then
				local Inertia = 0

				if GearRatio ~= 0 then
					Inertia = InputInertia / GearRatio
				end

				Link.ReqTq = abs(Ent:Calc(InputRPM * GearRatio, Inertia) * GearRatio) * Clutch
				TotalReqTq = TotalReqTq + abs(Link.ReqTq)
			end
		end

		local DoubleDiff = SelfTbl.DoubleDiff
		local SteerRate  = SelfTbl.SteerRate

		for Wheel, Link in pairs(SelfTbl.Wheels) do
			Link.ReqTq = 0

			if GearRatio ~= 0 then
				local RPM = CalcWheel(self, Link, Wheel, SelfWorld)
				local Clutch = Link.Side == 0 and LClutch or RClutch
				local OnRPM = ((InputRPM > 0 and RPM < InputRPM) or (InputRPM < 0 and RPM > InputRPM))

				if Clutch > 0 and OnRPM then
					local Multiplier = 1

					if DoubleDiff and SteerRate ~= 0 then
						local Rate = SteerRate * 2

						-- this actually controls the RPM of the wheels, so the steering rate is correct
						if Link.Side == 0 then
							Multiplier = min(0, Rate) + 1
						else
							Multiplier = -max(0, Rate) + 1
						end
					end

					Link.ReqTq = (InputRPM * Multiplier - RPM) * InputInertia * Clutch

					TotalReqTq = TotalReqTq + abs(Link.ReqTq)
				end
			end
		end

		SelfTbl.TotalReqTq = TotalReqTq
		TorqueOutput = min(TotalReqTq, SelfTbl.MaxTorque)
		SelfTbl.TorqueOutput = TorqueOutput

		self:UpdateOverlay()

		return TorqueOutput
	end

	function ENT:Act(Torque, DeltaTime, MassRatio)

		local Loss = Clamp(((1 - 0.4) / 0.5) * ((self.ACF.Health / self.ACF.MaxHealth) - 1) + 1, 0.4, 1) --internal torque loss from damaged
		local Slop = self.Automatic and 0.9 or 1 --internal torque loss from inefficiency
		local ReactTq = 0
		-- Calculate the ratio of total requested torque versus what's avaliable, and then multiply it but the current gearratio
		local AvailTq = 0
		local GearRatio = self.GearRatio

		if Torque ~= 0 and GearRatio ~= 0 then
			AvailTq = min(abs(Torque) / self.TotalReqTq, 1) / GearRatio * -(-Torque / abs(Torque)) * Loss * Slop
		end

		for Ent, Link in pairs(self.GearboxOut) do
			Link:Transfer(Link.ReqTq * AvailTq)
			Ent:Act(Link.ReqTq * AvailTq, DeltaTime, MassRatio)
		end

		for Ent, Link in pairs(self.Wheels) do
			-- If the gearbox is braking, always

			local Brake = Link.Side == 0 and self.LBrake or self.RBrake
			
			local WheelTorque = Link.ReqTq * AvailTq
			ReactTq = ReactTq + WheelTorque

			Link:Transfer(WheelTorque)
			ActWheel(Link, Ent, WheelTorque, DeltaTime, Brake)
		end

		if ReactTq ~= 0 then
			local BoxPhys = self:GetAncestor():GetPhysicsObject()

			if IsValid(BoxPhys) then
				BoxPhys:ApplyTorqueCenter(self:GetRight() * Clamp(2 * deg(ReactTq * MassRatio) * DeltaTime, -500000, 500000))
			end
		end

		self.LastActive = Clock.CurTime
	end
end ----------------------------------------------------

--[[do -- Braking ------------------------------------------
	local function BrakeWheel(Link, Wheel, Brake)
		local Phys      = Wheel:GetPhysicsObject()
		local AntiSpazz = 1

		if not Phys:IsMotionEnabled() then return end -- skipping entirely if its frozen

		if Brake > 100 then
			local Overshot = abs(Link.LastVel - Link.Vel) > abs(Link.LastVel) -- Overshot the brakes last tick?
			local Rate     = Overshot and 0.2 or 0.002 -- If we overshot, cut back agressively, if we didn't, add more brakes slowly

			Link.AntiSpazz = (1 - Rate) * Link.AntiSpazz + (Overshot and 0 or Rate) -- Low pass filter on the antispazz

			AntiSpazz = min(Link.AntiSpazz * 10000 / Brake, 1) -- Anti-spazz relative to brake power
		end

		Link.LastVel = Link.Vel

		Phys:AddAngleVelocity(-Link.Axis * Link.Vel * AntiSpazz * Brake * 0.01)
	end

	function ENT:ApplyBrakes() -- This is just for brakes
		if self.Disabled then return end -- Illegal brakes man
		if not self.Braking then return end -- Kills the whole thing if its not supposed to be running
		if not next(self.Wheels) then return end -- No brakes for the non-wheel users
		if self.LastBrake == Clock.CurTime then return end -- Don't run this twice in a tick

		local BoxPhys = self:GetAncestor():GetPhysicsObject()
		local SelfWorld = BoxPhys:LocalToWorldVector(BoxPhys:GetAngleVelocity())
		local DeltaTime = Clock.DeltaTime

		for Wheel, Link in pairs(self.Wheels) do
			local Brake = Link.Side == 0 and self.LBrake or self.RBrake

			if Brake > 0 then -- regular ol braking

				CalcWheel(self, Link, Wheel, SelfWorld) -- Updating the link velocity
				BrakeWheel(Link, Wheel, Brake, DeltaTime)
			else

			end
		end

		self.LastBrake = Clock.CurTime

		timer.Simple(DeltaTime, function()
			if not IsValid(self) then return end

			self:ApplyBrakes()
		end)
	end
end]] ----------------------------------------------------

do -- Duplicator Support -------------------------------
	function ENT:PreEntityCopy()
		if next(self.Wheels) then
			local Wheels = {}

			for Ent in pairs(self.Wheels) do
				Wheels[#Wheels + 1] = Ent:EntIndex()
			end

			duplicator.StoreEntityModifier(self, "ACFWheels", Wheels)
		end

		if next(self.GearboxOut) then
			local Entities = {}

			for Ent in pairs(self.GearboxOut) do
				Entities[#Entities + 1] = Ent:EntIndex()
			end

			duplicator.StoreEntityModifier(self, "ACFGearboxes", Entities)
		end

		--Wire dupe info
		BaseClass.PreEntityCopy(self)
	end

	function ENT:PostEntityPaste(Player, Ent, CreatedEntities)
		local EntMods = Ent.EntityMods

		-- Backwards compatibility
		if EntMods.WheelLink then
			local Entities = EntMods.WheelLink.entities

			for _, EntID in ipairs(Entities) do
				self:Link(CreatedEntities[EntID])
			end

			EntMods.WheelLink = nil
		end

		if EntMods.ACFWheels then
			for _, EntID in ipairs(EntMods.ACFWheels) do
				self:Link(CreatedEntities[EntID])
			end

			EntMods.ACFWheels = nil
		end

		if EntMods.ACFGearboxes then
			for _, EntID in ipairs(EntMods.ACFGearboxes) do
				self:Link(CreatedEntities[EntID])
			end

			EntMods.ACFGearboxes = nil
		end

		BaseClass.PostEntityPaste(self, Player, Ent, CreatedEntities)
	end
end ----------------------------------------------------

do	-- NET SURFER 2.0
	util.AddNetworkString("ACF_RequestGearboxInfo")
	util.AddNetworkString("ACF_InvalidateGearboxInfo")

	function ENT:InvalidateClientInfo()
		net.Start("ACF_InvalidateGearboxInfo")
			net.WriteEntity(self)
		net.Broadcast()
	end

	net.Receive("ACF_RequestGearboxInfo", function(_, Ply)
		local Entity = net.ReadEntity()

		if IsValid(Entity) then
			local Inputs = {}
			local OutputL = {}
			local OutputR = {}
			local Data = {
				In = Entity.In,
				OutL = Entity.OutL,
				OutR = Entity.OutR
			}

			if next(Entity.GearboxIn) then
				for E in pairs(Entity.GearboxIn) do
					Inputs[#Inputs + 1] = E:EntIndex()
				end
			end

			if next(Entity.Engines) then
				for E in pairs(Entity.Engines) do
					Inputs[#Inputs + 1] = E:EntIndex()
				end
			end

			if next(Entity.GearboxOut) then
				for E, L in pairs(Entity.GearboxOut) do
					if L.Side == 0 then
						OutputL[#OutputL + 1] = E:EntIndex()
					else
						OutputR[#OutputR + 1] = E:EntIndex()
					end
				end
			end

			if next(Entity.Wheels) then
				for E, L in pairs(Entity.Wheels) do
					if L.Side == 0 then
						OutputL[#OutputL + 1] = E:EntIndex()
					else
						OutputR[#OutputR + 1] = E:EntIndex()
					end
				end
			end

			net.Start("ACF_RequestGearboxInfo")
				net.WriteEntity(Entity)
				net.WriteString(util.TableToJSON(Data))
				net.WriteString(util.TableToJSON(Inputs))
				net.WriteString(util.TableToJSON(OutputL))
				net.WriteString(util.TableToJSON(OutputR))
			net.Send(Ply)
		end
	end)
end

do -- Miscellaneous ------------------------------------
	function ENT:Enable()
		if self.Automatic then
			self:ChangeDrive(self.OldGear)
		else
			self:ChangeGear(self.OldGear)
		end

		self.OldGear = nil

		self:UpdateOverlay()
	end

	function ENT:Disable()
		self.OldGear = self.Automatic and self.Drive or self.Gear

		if self.Automatic then
			self:ChangeDrive(0)
		else
			self:ChangeGear(0)
		end

		self:UpdateOverlay()
	end

	-- Prevent people from changing bodygroup
	function ENT:CanProperty(_, Property)
		return Property ~= "bodygroups"
	end

	function ENT:OnRemove()
		local Class = self.ClassData

		if Class.OnLast then
			Class.OnLast(self, Class)
		end

		hook.Run("ACF_OnEntityLast", "acf_gearbox", self, Class)

		for Engine in pairs(self.Engines) do
			self:Unlink(Engine)
		end

		for Wheel in pairs(self.Wheels) do
			self:Unlink(Wheel)
		end

		for Gearbox in pairs(self.GearboxIn) do
			Gearbox:Unlink(self)
		end

		for Gearbox in pairs(self.GearboxOut) do
			self:Unlink(Gearbox)
		end

		timer.Remove("ACF Gearbox Clock " .. self:EntIndex())

		WireLib.Remove(self)
	end
end ----------------------------------------------------
