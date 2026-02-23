Config.Locations = {
    public_bench = {
        label = 'Public Workbench',
        coords = vec4(-347.07, -133.64, 39.01, 340.0),
        prop = {
            enabled = true,
            model = 'xm3_prop_xm3_bench_04b',
            coords = vec4(-255.03, -1304.39, 30.3, 176.45),
        },
        recipes = { 'Illegal', 'Utility' },
        jobs = false,
        blip = {
            enabled = true,
            sprite = 566,
            color = 2,
            scale = 0.75,
            display = 4,
            shortRange = true
        }
    },
    mechanic_bench = {
        label = 'Mechanic Bench',
        coords = vec3(-228.96, -1327.71, 30.89),
        prop = {
            enabled = false,
        },
        recipes = { 'Utility' },
        jobs = {
            mechanic = 0
        },
        blip = {
            enabled = true,
            sprite = 446,
            color = 5,
            scale = 0.75,
            display = 4,
            shortRange = true
        }
    }
}
