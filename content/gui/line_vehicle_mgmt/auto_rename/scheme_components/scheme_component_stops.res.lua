function data()
	return {
		type = "rename_scheme_component",
		data = {
			schemeComponentNameRaw = "stops",
			schemeComponentNameTranslated = _("Stops"),
			renameFnDefinition = {
				fileName = resolve("scheme_component_stops.script@renameFn"),
				params = {},
			},
		},
	}
end
