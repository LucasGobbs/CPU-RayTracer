package raytracer

import "core:math"
trace_ray :: proc(ray: Ray, depth: int, world: ^World) -> Color {
	if depth <= 0 do return Color{.0, .0, .0}

	hit_record, hitted := hit_objects(world, ray, .001, math.INF_F64)

	if hitted {
		has_scattered, scattered_ray, material_color := material_scatter(ray, hit_record)
		if has_scattered {
			return material_color * trace_ray(scattered_ray, depth - 1, world)
		}

		return material_color
	}

	unit_direction := vec_unit(ray.direction)
	a := .5 * (unit_direction.y + 1)
	return (1.0 - a) * Color{1.0, 1.0, 1.0} + a * Color{.5, .7, 1.0}
}
