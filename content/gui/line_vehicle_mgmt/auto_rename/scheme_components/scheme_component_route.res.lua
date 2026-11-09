function data()
	return {
		type = "rename_scheme_component",
		data = {
			schemeComponentNameRaw = "route",
			schemeComponentNameTranslated = _("Route"),
			renameFnDefinition = {
				fileName = resolve("scheme_component_route.script@renameFn"),
				params = {},
			},
		},
	}
end
