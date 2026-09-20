package raytracer
import "../utils"
import "core:math"
import "core:math/rand"
// MATERIAL ================================================================================================
// =========================================================================================================
Material :: union {
	LambertianMaterial,
	MetalMaterial,
	DieletricMaterial,
	DiffuseLightMaterial,
}
material_scatter :: proc(ray_in: Ray, hit_record: HitRecord) -> (bool, Ray, Color) {
	switch value in hit_record.material {
	case LambertianMaterial:
		return lambertian_scatter(ray_in, hit_record)
	case MetalMaterial:
		return metal_scatter(ray_in, hit_record)
	case DieletricMaterial:
		return dieletric_scatter(ray_in, hit_record)
	case DiffuseLightMaterial:
		return diffuse_scatter(ray_in, hit_record)
	}

	return false, Ray{}, Black
}


// LAMBERTIAN (DIFUSE) =====================================================================================
// =========================================================================================================
LambertianMaterial :: struct {
	albedo:   Color,

	// Black as Default
	emission: Color,
}

lambertian_create :: proc(albedo: Color) -> LambertianMaterial {
	return LambertianMaterial{albedo = albedo, emission = Black}
}

lambertian_random :: proc() -> Material {
	return LambertianMaterial{albedo = color_random()}
}

lambertian_scatter :: proc(ray_in: Ray, hit_record: HitRecord) -> (bool, Ray, Color) {
	scatter_direction := hit_record.normal + vec3_rand_unit()

	if vec3_is_near_zero(scatter_direction) do scatter_direction = hit_record.normal


	scattered := Ray {
		origin    = hit_record.position,
		direction = scatter_direction,
		time      = ray_in.time,
	}

	attenuation := hit_record.material.(LambertianMaterial).albedo

	return true, scattered, attenuation
}

// METAL ===================================================================================================
// =========================================================================================================
MetalMaterial :: struct {
	albedo:   Color,
	fuzz:     f64,
	// Black as Default
	emission: Color,
}

metal_create :: proc(albedo: Color, fuzz: f64) -> MetalMaterial {
	return MetalMaterial{albedo = albedo, fuzz = fuzz, emission = Black}
}

metal_random :: proc() -> Material {
	return MetalMaterial{albedo = color_random(), fuzz = rand.float64()}
}
metal_scatter :: proc(ray_in: Ray, hit_record: HitRecord) -> (bool, Ray, Color) {
	metal_material := hit_record.material.(MetalMaterial)

	reflected_direction := vec3_reflect(ray_in.direction, hit_record.normal)
	reflected_direction = vec_unit(reflected_direction) + (metal_material.fuzz * vec3_rand_unit())

	has_scattered := vec_dot(reflected_direction, hit_record.normal) > 0
	if !has_scattered do return false, Ray{}, Color{}
	scattered := Ray {
		origin    = hit_record.position,
		direction = reflected_direction,
		time      = ray_in.time,
	}

	attenuation := metal_material.albedo


	return true, scattered, attenuation
}


// DIELETRIC ===============================================================================================
// =========================================================================================================
DieletricMaterial :: struct {
	refraction_index: f64,
	// Black as Default
	emission:         Color,
}

dieletric_create :: proc(refraction_index: f64) -> DieletricMaterial {
	return DieletricMaterial{refraction_index = refraction_index, emission = Black}
}

dieletric_random :: proc() -> Material {
	return dieletric_create(refraction_index = rand.float64())
}

// Scatter based on function
dieletric_scatter :: proc(ray_in: Ray, hit_record: HitRecord) -> (bool, Ray, Color) {
	refraction_index := hit_record.material.(DieletricMaterial).refraction_index
	attenuation := White
	ri := hit_record.front_face ? (1.0 / refraction_index) : refraction_index

	unit_direction := vec_unit(ray_in.direction)
	cos_theta := math.min(vec_dot(-unit_direction, hit_record.normal), 1.0)
	sin_theta := math.sqrt(1.0 - cos_theta * cos_theta)

	cannot_refract := ri * sin_theta > 1.0

	direction: Vec3 = ---

	if cannot_refract || reflectance(cos_theta, refraction_index) > rand.float64() {
		direction = vec3_reflect(unit_direction, hit_record.normal)
	} else {
		direction = vec3_refract(unit_direction, hit_record.normal, ri)
	}

	refracted := vec3_refract(unit_direction, hit_record.normal, refraction_index)

	scattered := Ray {
		origin    = hit_record.position,
		direction = direction,
		time      = ray_in.time,
	}

	return true, scattered, attenuation
}

// Schlick Approximation
reflectance :: proc(cosine: f64, refraction_index: f64) -> f64 {
	r0 := (1.0 - refraction_index) / (1.0 + refraction_index)
	r0 = r0 * r0
	return r0 + (1 - r0) * math.pow(1 - cosine, 5)
}


// Light ===============================================================================================
// =========================================================================================================
DiffuseLightMaterial :: struct {
	emission: Color,
}

diffuse_create :: proc(emission: Color) -> DiffuseLightMaterial {
	return DiffuseLightMaterial{emission = emission}
}

diffuse_random :: proc() -> Material {
	return diffuse_create(
		Color {
			rand.float64_range(.8, 1.0),
			rand.float64_range(.8, 1.0),
			rand.float64_range(.8, 1.0),
		},
	)
}

// Scatter based on function
diffuse_scatter :: proc(ray_in: Ray, hit_record: HitRecord) -> (bool, Ray, Color) {
	emission_color := hit_record.material.(DiffuseLightMaterial).emission
	return false, ray_in, emission_color
}
