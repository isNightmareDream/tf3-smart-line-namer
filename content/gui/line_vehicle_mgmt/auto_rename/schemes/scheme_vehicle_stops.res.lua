function data()
	return {
		type = "rename_scheme",
		data = {
			schemeNameRaw = "vehicle_stops",
			schemeNameTranslated = _("Vehicle - Stops"),
			sortKey = 10,
			formatString = "{key1}",
			formatParams = {
				["key1"] = "stops",
			},
		},
	}
end
