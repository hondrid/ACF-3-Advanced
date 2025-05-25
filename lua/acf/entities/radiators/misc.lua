local Radiators = ACF.Classes.Radiators

Radiators.Register("Rad_M", {
	Name		= "Miscellaneous",
	Description	= "Radiator models",
})

do
	Radiators.RegisterItem("Prop_Radiator", "Rad_M", {
		Name		= "Prop_Radiator",
		Description	= "A simple radiator",
		Model		= "models/props_c17/furnitureradiator001a.mdl",
		SurfaceArea	= 1839.7,
		Volume		= 4384.1,
		Density 	= 1.11,
		Shape       = "Rad",
		Preview = {
			FOV = 124,
		},
	})
end