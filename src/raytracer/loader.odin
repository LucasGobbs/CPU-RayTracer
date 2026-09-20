package raytracer

import scene_data "../scene"
import "collider"
CamParams :: struct {
	position:      Point3,
	look_at:       Point3,
	vfov:          f64,
	ratio:         f64,
	samples:       int,
	max_depth:     int,
	defocus_angle: f64,
	focus_dist:    f64,
}

build_camera :: proc(p: ^CamParams, raytracer_params: RaytracerParams) -> Camera {
	return camera_create(
		raytracer_params = raytracer_params,
		ratio = p.ratio,
		position = p.position,
		look_at = p.look_at,
		samples = p.samples,
		max_depth = p.max_depth,
		defocus_angle = p.defocus_angle,
		focus_dist = p.focus_dist,
		vfov = p.vfov,
	)
}

// load_from_scene converts the data-only scene model into camera settings and
// the concrete World consumed by the raytracer.
load_from_scene :: proc(desc: ^scene_data.Scene) -> (CamParams, World) {
	params := CamParams {
		position      = Point3(desc.camera.position),
		look_at       = Point3(desc.camera.look_at),
		vfov          = desc.camera.vfov,
		ratio         = desc.camera.ratio,
		samples       = desc.camera.samples,
		max_depth     = desc.camera.max_depth,
		defocus_angle = desc.camera.defocus_angle,
		focus_dist    = desc.camera.focus_dist,
	}

	world := world_create(len(desc.objects))
	for object in desc.objects {
		switch object.type {
		case .sphere:
			world_append_sphere(
				&world,
				collider.sphere_collider_create(
					Vec3(object.position),
					Vec3(object.direction),
					object.radius,
				),
				load_material(object.material),
			)
		}
	}

	// Invariant: quads come after all spheres — global collider ids (and
	// therefore materials) index spheres first, then quads.
	for quad in desc.quads {
		world_append_quad(
			&world,
			collider.quad_collider_create(Vec3(quad.corner), Vec3(quad.edge_u), Vec3(quad.edge_v)),
			load_material(quad.material),
		)
	}

	return params, world
}

load_material :: proc(material: scene_data.SceneMaterial) -> Material {
	switch material.kind {
	case .lambertian:
		return LambertianMaterial{albedo = Color(material.albedo)}
	case .metal:
		return MetalMaterial{albedo = Color(material.albedo), fuzz = material.fuzz}
	case .dielectric:
		return DieletricMaterial{refraction_index = material.refraction_index}
	case .diffuse_light:
		return DiffuseLightMaterial{emission = Color{1.0, 1.0, 1.0}}
	case:
		return LambertianMaterial{albedo = Color{1, 0, 1}}
	}
}
