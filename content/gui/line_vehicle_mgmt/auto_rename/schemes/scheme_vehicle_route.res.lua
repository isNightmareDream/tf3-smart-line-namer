function data()
	return {
		type = "rename_scheme",
		data = {
			schemeNameRaw = "vehicle_route",
			schemeNameTranslated = _("Vehicle - Route"),
			sortKey = 9,
			formatString = "{key1}",
			formatParams = {
				["key1"] = "route",
			},
		},
	}
end
