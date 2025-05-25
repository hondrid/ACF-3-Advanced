local Radiators = ACF.Classes.Radiators

Radiators.Register("Rad_B", {
	Name		= "Radiator Box",
	Description	= "Scalable Radiator box; required for advanced engines to work.",
	Scalable	= true,
	Model		= "models/holograms/hq_rcube.mdl",
	Material	= "models/props_canal/metalcrate001d",
	Shape		= "Box",
	NameType	= "Radiator",
	Unlinkable	= false,
	Density	= 1.11,
	Preview = {
		FOV = 120,
	},
	CalcVolume = function(Size, Wall)
		local InteriorVolume = (Size.x - Wall) * (Size.y - Wall) * (Size.z - Wall) -- Math degree

		local Area = (2 * Size.x * Size.y) + (2 * Size.y * Size.z) + (2 * Size.x * Size.z)
		local Volume = InteriorVolume - (Area * Wall)

		return Volume, Area
	end,
	
	CalcOverlaySize = function(Entity)
		local X, Y, Z = Entity:GetSize():Unpack()
		X = math.Round(X, 2)
		Y = math.Round(Y, 2)
		Z = math.Round(Z, 2)

		return "Size: " .. X .. "x" .. Y .. "x" .. Z .. "\n\n"
	end,
	MenuSettings = function(SizeX, SizeY, SizeZ)
		SizeX:SetVisible(true)
		SizeY:SetVisible(true)
		SizeZ:SetVisible(true)


		SizeX:SetText("Radiator Length")
		SizeZ:SetText("Radiator Height")
	end
})

-- NOTE: The X and Y values for older containers are swapped on purpose to match old model shapes

do -- Size 1 container compatibility
	Radiators.AddAlias("Rad_B", "Rad_1")

	Radiators.RegisterItem("Rad_1x1x1", "Rad_B", {
		Size	= Vector(2.5, 10, 10),
		Shape	= "Box"
	})

	Radiators.RegisterItem("Rad_1x1x2", "Rad_B", {
		Size	= Vector(2.5, 10, 20),
		Shape	= "Box"
	})

	Radiators.RegisterItem("Rad_1x1x4", "Rad_B", {
		Size	= Vector(2.5, 10, 40),
		Shape	= "Box"
	})

	Radiators.RegisterItem("Rad_1x2x1", "Rad_B", {
		Size	= Vector(2.5, 20, 10),
		Shape	= "Box"
	})

	Radiators.RegisterItem("Rad_1x2x2", "Rad_B", {
		Size	= Vector(2.5, 20, 20),
		Shape	= "Box"
	})

	Radiators.RegisterItem("Rad_1x2x4", "Rad_B", {
		Size	= Vector(2.5, 20, 40),
		Shape	= "Box"
	})

	Radiators.RegisterItem("Rad_1x4x1", "Rad_B", {
		Size	= Vector(2.5, 40, 10),
		Shape	= "Box"
	})

	Radiators.RegisterItem("Rad_1x4x2", "Rad_B", {
		Size	= Vector(2.5, 40, 20),
		Shape	= "Box"
	})

	Radiators.RegisterItem("Rad_1x4x4", "Rad_B", {
		Size	= Vector(2.5, 40, 40),
		Shape	= "Box"
	})

	Radiators.RegisterItem("Rad_1x6x1", "Rad_B", {
		Size	= Vector(2.5, 60, 10),
		Shape	= "Box"
	})

	Radiators.RegisterItem("Rad_1x6x2", "Rad_B", {
		Size	= Vector(2.5, 60, 20),
		Shape	= "Box"
	})

	Radiators.RegisterItem("Rad_1x6x4", "Rad_B", {
		Size	= Vector(2.5, 60, 40),
		Shape	= "Box"
	})

	Radiators.RegisterItem("Rad_1x8x1", "Rad_B", {
		Size	= Vector(2.5, 80, 10),
		Shape	= "Box"
	})

	Radiators.RegisterItem("Rad_1x8x2", "Rad_B", {
		Size	= Vector(2.5, 80, 20),
		Shape	= "Box"
	})

	Radiators.RegisterItem("Rad_1x8x4", "Rad_B", {
		Size	= Vector(2.5, 80, 40),
		Shape	= "Box"
	})
end

do -- Size 2 container compatibility
	Radiators.AddAlias("Rad_B", "Rad_2")

	Radiators.RegisterItem("Rad_2x2x1", "Rad_B", {
		Size	= Vector(20, 20, 2.5),
		Shape	= "Box"
	})

	Radiators.RegisterItem("Rad_2x4x1", "Rad_B", {
		Size	= Vector(20, 40, 2.5),
		Shape	= "Box"
	})

	Radiators.RegisterItem("Rad_2x6x1", "Rad_B", {
		Size	= Vector(20, 60, 2.5),
		Shape	= "Box"
	})

	Radiators.RegisterItem("Rad_2x8x1", "Rad_B", {
		Size	= Vector(20, 80, 2.5),
		Shape	= "Box"
	})

end

do -- Size 4 container compatibility
	Radiators.AddAlias("Rad_B", "Rad_4")

	Radiators.RegisterItem("Rad_4x4x1", "Rad_B", {
		Size	= Vector(40, 40, 2.5),
		Shape	= "Box"
	})
	
	Radiators.RegisterItem("Rad_4x6x1", "Rad_B", {
		Size	= Vector(40, 60, 2.5),
		Shape	= "Box"
	})

	Radiators.RegisterItem("Rad_4x8x1", "Rad_B", {
		Size	= Vector(40, 80, 2.5),
		Shape	= "Box"
	})

end

do -- Size 6 container compatibility
	Radiators.AddAlias("Rad_B", "Rad_6")

	Radiators.RegisterItem("Rad_6x6x1", "Rad_B", {
		Size	= Vector(60, 60, 2.5),
		Shape	= "Box"
	})
end

do -- Size 8 container compatibility
	Radiators.AddAlias("Rad_B", "Rad_8")

	Radiators.RegisterItem("Rad_8x8x1", "Rad_B", {
		Size	= Vector(80, 80, 2.5),
		Shape	= "Box"
	})
end