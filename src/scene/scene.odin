package scene

import "../utils"
import "core:math"
import "core:math/rand"

MaterialType :: enum {
	lambertian,
	metal,
	dielectric,
	diffuse_light,
}

ObjectType :: enum {
	sphere,
}

SceneMaterial :: struct {
	kind:             MaterialType,
	albedo:           [3]f64,
	fuzz:             f64,
	refraction_index: f64,
	emission:         [3]f64,
}

SceneObject :: struct {
	type:      ObjectType,
	position:  [3]f64,
	direction: [3]f64,
	radius:    f64,
	material:  SceneMaterial,
}

// Parallelogram from a corner plus two edge vectors; carries no motion.
SceneQuad :: struct {
	corner:   [3]f64,
	edge_u:   [3]f64,
	edge_v:   [3]f64,
	material: SceneMaterial,
}

SceneCamera :: struct {
	position:      [3]f64,
	look_at:       [3]f64,
	vfov:          f64,
	ratio:         f64,
	samples:       int,
	max_depth:     int,
	defocus_angle: f64,
	focus_dist:    f64,
}

Scene :: struct {
	name:    string, // identifier used in render output filenames
	camera:  SceneCamera,
	objects: [dynamic]SceneObject,
	quads:   [dynamic]SceneQuad,
}

scene_destroy :: proc(scene: ^Scene) {
	delete(scene.objects)
	delete(scene.quads)
}

scene_camera :: proc(
	position: [3]f64,
	look_at: [3]f64,
	vfov: f64,
	defocus_angle: f64,
	focus_dist: f64,
	samples: int,
	max_depth: int,
) -> SceneCamera {
	return SceneCamera {
		position = position,
		look_at = look_at,
		vfov = vfov,
		ratio = 16.0 / 9.0,
		samples = samples,
		max_depth = max_depth,
		defocus_angle = defocus_angle,
		focus_dist = focus_dist,
	}
}

scene_with_camera :: proc(camera: SceneCamera, capacity: int) -> Scene {
	return Scene {
		camera = camera,
		objects = make([dynamic]SceneObject, 0, capacity),
		quads = make([dynamic]SceneQuad, 0, 4),
	}
}

append_ground :: proc(scene: ^Scene) {
	append(
		&scene.objects,
		SceneObject {
			type = .sphere,
			position = {0, -100.5, -1},
			direction = {.0, .0, .0},
			radius = 100.0,
			material = SceneMaterial{kind = .metal, albedo = {0.4, 0.4, 0.4}},
		},
	)
}

append_material_test_spheres :: proc(scene: ^Scene) {
	append(
		&scene.objects,
		SceneObject {
			type = .sphere,
			position = {-1.1, 0, -1.5},
			direction = {.0, .0, .0},
			radius = 0.5,
			material = SceneMaterial{kind = .dielectric, refraction_index = 1.5},
		},
	)
	append(
		&scene.objects,
		SceneObject {
			type = .sphere,
			position = {-1.1, 0, -1.5},
			direction = {.0, .0, .0},
			radius = 0.4,
			material = SceneMaterial{kind = .dielectric, refraction_index = 1.0 / 1.5},
		},
	)
	append(
		&scene.objects,
		SceneObject {
			type = .sphere,
			position = {0, 0, -1.5},
			direction = {.0, .0, .0},
			radius = 0.5,
			material = SceneMaterial{kind = .lambertian, albedo = {0.8, 0.3, 0.3}},
		},
	)
	append(
		&scene.objects,
		SceneObject {
			type = .sphere,
			position = {2.1, 0, -1.5},
			direction = {.0, .0, .0},
			radius = 1.0,
			material = SceneMaterial{kind = .metal, albedo = {0.9, 0.2, 0.1}, fuzz = 0.001},
		},
	)
}

// basic_scene is a small, fast scene for checking camera and materials.
basic_scene :: proc() -> Scene {
	scene := scene_with_camera(scene_camera({0, 1, 4}, {0, 0, -1.5}, 45, 0, 5, 25, 10), 5)
	scene.name = "basic"
	append_ground(&scene)
	append_material_test_spheres(&scene)
	append(
		&scene.quads,
		SceneQuad {
			corner = {2, 0.2, -3.5},
			edge_u = {2, 0, 0},
			edge_v = {0, 2, 0},
			material = SceneMaterial{kind = .lambertian, albedo = {0.2, 0.6, 0.9}},
		},
	)
	return scene
}

cornell_basic_scene :: proc() -> Scene {
	scene := scene_with_camera(scene_camera({0, 1, 4}, {0, 0, -1.5}, 45, 0, 5, 25, 10), 5)
	scene.name = "cornell_basic"
	append_ground(&scene)
	append_material_test_spheres(&scene)
	append(
		&scene.quads,
		SceneQuad {
			corner = {2, 0.2, -3.5},
			edge_u = {2, 0, 0},
			edge_v = {0, 2, 0},
			material = SceneMaterial{kind = .lambertian, albedo = {0.2, 0.6, 0.9}},
		},
	)
	return scene
}

// materials_scene isolates the three material types at different depths.
materials_scene :: proc() -> Scene {
	scene := scene_with_camera(scene_camera({0, 1, 5}, {0, 0, -3}, 40, 0, 6, 50, 20), 4)
	scene.name = "materials"
	append_ground(&scene)
	append(
		&scene.objects,
		SceneObject {
			type = .sphere,
			position = {-2, 0, -3},
			radius = 1,
			material = SceneMaterial{kind = .lambertian, albedo = {0.8, 0.2, 0.2}},
		},
	)
	append(
		&scene.objects,
		SceneObject {
			type = .sphere,
			position = {0, 0, -3},
			radius = 1,
			material = SceneMaterial{kind = .metal, albedo = {0.8, 0.8, 0.8}, fuzz = 0.05},
		},
	)
	append(
		&scene.objects,
		SceneObject {
			type = .sphere,
			position = {2, 0, -3},
			radius = 1,
			material = SceneMaterial{kind = .dielectric, refraction_index = 1.5},
		},
	)
	return scene
}

// defocus_scene puts objects at several depths to tune aperture and focus_dist.
defocus_scene :: proc() -> Scene {
	scene := scene_with_camera(scene_camera({0, 1.5, 4}, {0, 0, -3}, 40, 6, 5, 50, 20), 5)
	scene.name = "defocus"
	append_ground(&scene)
	append(
		&scene.objects,
		SceneObject {
			type = .sphere,
			position = {-1.5, 0, -1},
			radius = 0.8,
			material = SceneMaterial{kind = .lambertian, albedo = {0.8, 0.2, 0.2}},
		},
	)
	append(
		&scene.objects,
		SceneObject {
			type = .sphere,
			position = {0, 0, -3},
			radius = 0.8,
			material = SceneMaterial{kind = .metal, albedo = {0.8, 0.8, 0.8}, fuzz = 0.05},
		},
	)
	append(
		&scene.objects,
		SceneObject {
			type = .sphere,
			position = {1.5, 0, -6},
			radius = 0.8,
			material = SceneMaterial{kind = .dielectric, refraction_index = 1.5},
		},
	)
	return scene
}

// random_scene contains only the ground and a configurable random grid.
random_scene :: proc(grid_radius: int = 5) -> Scene {
	side := 2 * grid_radius
	capacity := side * side + 1
	scene := scene_with_camera(
		scene_camera({-2, 1.5, 1}, {0, 0, -1.5}, 40, 0.0, 3.4, 100, 50),
		capacity,
	)
	scene.name = "random"
	append_ground(&scene)
	append_random_grid(&scene, grid_radius)
	return scene
}

// complex_scene matches the original scene assembled in main.
complex_scene :: proc() -> Scene {
	scene := random_scene(5)
	scene.name = "complex"
	append_material_test_spheres(&scene)
	// append(
	// 	&scene.quads,
	// 	SceneQuad {
	// 		corner = {.5, -1.1, -3.8},
	// 		edge_u = {4, 0, 0},
	// 		edge_v = {0, 3, 0},
	// 		material = SceneMaterial{kind = .lambertian, albedo = {0.1, 0.2, 0.3}},
	// 	},
	// )
	// append(
	// 	&scene.quads,
	// 	SceneQuad {
	// 		corner = {.6, -1, -3.5},
	// 		edge_u = {4, 0, 0},
	// 		edge_v = {0, 3, 0},
	// 		material = SceneMaterial{kind = .metal, albedo = {0.6, 0.6, 0.8}},
	// 	},
	// )
	return scene
}

// rotate_y rotates a vector around the origin's y axis (RTOW convention).
rotate_y :: proc(v: [3]f64, degrees: f64) -> [3]f64 {
	radians := utils.degrees_to_radians(degrees)
	s := math.sin(radians)
	c := math.cos(radians)
	return {c * v.x + s * v.z, v.y, -s * v.x + c * v.z}
}

// append_cuboid bakes a full parallelepiped as 6 quads: build axis-aligned from
// corners a..b, rotate every face around y through the origin, then translate.
append_cuboid :: proc(
	scene: ^Scene,
	a, b: [3]f64,
	rotation_deg: f64,
	offset: [3]f64,
	material: SceneMaterial,
) {
	dx := [3]f64{b.x - a.x, 0, 0}
	dy := [3]f64{0, b.y - a.y, 0}
	dz := [3]f64{0, 0, b.z - a.z}

	faces := [6]SceneQuad {
		{corner = {a.x, a.y, b.z}, edge_u = dx, edge_v = dy, material = material}, // front
		{corner = {b.x, a.y, b.z}, edge_u = -dz, edge_v = dy, material = material}, // right
		{corner = {b.x, a.y, a.z}, edge_u = -dx, edge_v = dy, material = material}, // back
		{corner = {a.x, a.y, a.z}, edge_u = dz, edge_v = dy, material = material}, // left
		{corner = {a.x, b.y, b.z}, edge_u = dx, edge_v = -dz, material = material}, // top
		{corner = {a.x, a.y, a.z}, edge_u = dx, edge_v = dz, material = material}, // bottom
	}
	for face in faces {
		face := face
		face.corner = rotate_y(face.corner, rotation_deg) + offset
		face.edge_u = rotate_y(face.edge_u, rotation_deg)
		face.edge_v = rotate_y(face.edge_v, rotation_deg)
		append(&scene.quads, face)
	}
}

cornell_scene :: proc() -> Scene {
	scene := scene_with_camera(
		scene_camera({278, 278, -800}, {278, 278, 0}, 40, 0, 10, 100, 50),
		32,
	)
	scene.name = "cornell"
	scene.camera.ratio = 1.0
	white := SceneMaterial {
		kind   = .lambertian,
		albedo = {0.73, 0.73, 0.73},
	}
	red := SceneMaterial {
		kind   = .lambertian,
		albedo = {0.65, 0.05, 0.05},
	}
	green := SceneMaterial {
		kind   = .lambertian,
		albedo = {0.12, 0.45, 0.15},
	}

	append(
		&scene.quads,
		SceneQuad {
			corner = {0, 0, 0},
			edge_u = {0, 555, 0},
			edge_v = {0, 0, 555},
			material = green,
		},
	) // left
	append(
		&scene.quads,
		SceneQuad {
			corner = {555, 0, 0},
			edge_u = {0, 555, 0},
			edge_v = {0, 0, 555},
			material = red,
		},
	) // right
	append(
		&scene.quads,
		SceneQuad {
			corner = {0, 0, 0},
			edge_u = {555, 0, 0},
			edge_v = {0, 0, 555},
			material = white,
		},
	) // floor
	append(
		&scene.quads,
		SceneQuad {
			corner = {0, 0, 555},
			edge_u = {555, 0, 0},
			edge_v = {0, 555, 0},
			material = white,
		},
	) // back
	append(
		&scene.quads,
		SceneQuad {
			corner = {555, 555, 555},
			edge_u = {-555, 0, 0},
			edge_v = {0, 0, -555},
			material = white,
		},
	) // ceiling
	append(
		&scene.quads,
		SceneQuad {
			corner = {343, 554, 332},
			edge_u = {-130, 0, 0},
			edge_v = {0, 0, -105},
			material = white,
		},
	) // light panel

	append_cuboid(&scene, {0, 0, 0}, {165, 330, 165}, 15, {265, 0, 295}, white)
	append_cuboid(&scene, {0, 0, 0}, {165, 165, 165}, -18, {130, 0, 65}, white)

	return scene
}

append_random_grid :: proc(scene: ^Scene, grid_radius: int) {
	for i in -grid_radius ..< grid_radius {
		for j in -grid_radius ..< grid_radius {
			append(&scene.objects, random_sphere(i, j))
		}
	}
}

random_color :: proc() -> [3]f64 {
	return {rand.float64(), rand.float64(), rand.float64()}
}

random_sphere :: proc(i, j: int) -> SceneObject {
	material: SceneMaterial
	switch rand.int_max(3) {
	case 0:
		material = SceneMaterial {
			kind   = .lambertian,
			albedo = random_color(),
		}
	case 1:
		material = SceneMaterial {
			kind   = .metal,
			albedo = random_color(),
			fuzz   = rand.float64(),
		}
	case:
		material = SceneMaterial {
			kind             = .dielectric,
			refraction_index = rand.float64(),
		}
	}

	return SceneObject {
		type = .sphere,
		position = {
			cast(f64)i + utils.random_f64_between_values(-0.5, 0.5),
			utils.random_f64_between_values(-0.5, 0.5),
			cast(f64)j + utils.random_f64_between_values(-0.5, 0.5),
		},
		direction = {
			utils.random_f64_between_values(-0.0000001, 0.0000001),
			utils.random_f64_between_values(-0.0000001, 0.0000001),
			utils.random_f64_between_values(-0.0000001, 0.0000001),
		},
		radius = utils.random_f64_between_values(0.05, 0.2),
		material = material,
	}
}
