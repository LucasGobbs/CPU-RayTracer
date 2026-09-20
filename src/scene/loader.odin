package scene

// Loads a Scene and its render settings from a JSON (JSON5-superset) config.
//
// Format rule: any numeric field may be a literal or a "min;max" string. The
// string form is a uniform range sampled once per generated object at build
// time. Fixed content is appended first (spheres, quads, cuboids), then the
// random grid — grid RNG is seeded by the top-level "seed" field, so the same
// file always produces the same world.
//
// Parsed as JSON5: comments and trailing commas are allowed in config files.

import "../utils"
import "core:encoding/json"
import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"

// Scalar is a fixed value (min == max, is_range false) or a uniform range.
Scalar :: struct {
	min:      f64,
	max:      f64,
	is_range: bool,
}

Vec3S :: [3]Scalar

RenderTarget :: struct {
	width:        f64,
	ratio:        f64,
	upscale:      f64,
	color_format: u8,
	threads:      int,
	accelerator:  string,
}

LoadedScene :: struct {
	scene:  Scene,
	render: RenderTarget,
	config: ConfigState,
}

// ConfigState keeps the parsed config tree alive so the preview can mutate
// the camera block on capture and save it back WITHOUT flattening the random
// grid recipe or losing the seed — the saved file stays small and seeded.
ConfigState :: struct {
	path: string, // owned
	root: json.Value, // owned; nil when the file gave no usable tree
}

config_state_destroy :: proc(state: ^ConfigState) {
	delete(state.path)
	if state.root != nil {
		json.destroy_value(state.root)
	}
	state.root = nil
}

// save_camera_capture writes the config with position/look_at/vfov replaced
// (other camera fields and the whole world recipe are preserved) next to the
// source file as "<name>-capture.json". Returns the new path (caller-owned).
save_camera_capture :: proc(
	state: ^ConfigState,
	position, look_at: [3]f64,
	vfov: f64,
) -> (string, bool) {
	root_obj, is_obj := state.root.(json.Object)
	if !is_obj {
		fmt.eprintfln("camera capture: no parsed config tree to update")
		return "", false
	}

	vec_to_json :: proc(v: [3]f64) -> json.Array {
		arr := make(json.Array, 3)
		arr[0] = json.Float(v.x)
		arr[1] = json.Float(v.y)
		arr[2] = json.Float(v.z)
		return arr
	}

	camera_obj: json.Object
	if existing, has := root_obj["camera"]; has {
		camera_obj, _ = existing.(json.Object)
	}
	if camera_obj == nil {
		camera_obj = make(json.Object)
		root_obj["camera"] = camera_obj
	}
	camera_obj["position"] = vec_to_json(position)
	camera_obj["look_at"] = vec_to_json(look_at)
	camera_obj["vfov"] = json.Float(vfov)

	data, marshal_err := json.marshal(state.root, {pretty = true, use_spaces = true, spaces = 2})
	if marshal_err != nil {
		fmt.eprintfln("camera capture: marshal failed: %v", marshal_err)
		return "", false
	}
	defer delete(data)

	name, _ := str_field(root_obj, "name", "scene")
	out_path := fmt.tprintf("%s/%s-capture.json", filepath.dir(state.path), name)
	if write_err := os.write_entire_file(out_path, data); write_err != nil {
		fmt.eprintfln("camera capture: cannot write %s (%v)", out_path, write_err)
		return "", false
	}
	return strings.clone(out_path), true
}

@(private = "file")
MaterialSpec :: struct {
	kind:             string,
	albedo:           Vec3S,
	fuzz:             Scalar,
	refraction_index: Scalar,
	emission:         Vec3S,
}

@(private = "file")
GridSpec :: struct {
	grid_radius: int,
	jitter:      Vec3S,
	direction:   Vec3S,
	radius:      Scalar,
	kinds:       []string,
	templates:   map[string]MaterialSpec,
}

fixed :: proc(v: f64) -> Scalar {
	return {min = v, is_range = false}
}

// Draws one sample; ranges consume the global RNG, fixed values do not.
sample :: proc(s: Scalar) -> f64 {
	return s.is_range ? utils.random_f64_between_values(s.min, s.max) : s.min
}

sample_vec :: proc(v: Vec3S) -> [3]f64 {
	return {sample(v.x), sample(v.y), sample(v.z)}
}

@(private = "file")
parse_range :: proc(text: string) -> (Scalar, bool) {
	parts := strings.split_n(text, ";", 2)
	defer delete(parts)
	if len(parts) != 2 {
		fmt.eprintfln("scene config: expected \"min;max\" range, got %q", text)
		return {}, false
	}
	lo, ok_lo := strconv.parse_f64(strings.trim_space(parts[0]))
	hi, ok_hi := strconv.parse_f64(strings.trim_space(parts[1]))
	if !ok_lo || !ok_hi {
		fmt.eprintfln("scene config: bad numbers in range %q", text)
		return {}, false
	}
	return {min = lo, max = hi, is_range = true}, true
}

@(private = "file")
parse_scalar_value :: proc(v: json.Value) -> (Scalar, bool) {
	#partial switch x in v {
	case json.Float:
		return fixed(x), true
	case json.Integer:
		return fixed(f64(x)), true
	case json.String:
		return parse_range(x)
	}
	fmt.eprintfln("scene config: expected number or \"min;max\", got %v", v)
	return {}, false
}

@(private = "file")
scalar_field :: proc(obj: json.Object, key: string, default: f64) -> (Scalar, bool) {
	v, found := obj[key]
	if !found {
		return fixed(default), true
	}
	return parse_scalar_value(v)
}

@(private = "file")
vec_field :: proc(obj: json.Object, key: string, default: [3]f64) -> (Vec3S, bool) {
	out := Vec3S{fixed(default.x), fixed(default.y), fixed(default.z)}
	v, found := obj[key]
	if !found {
		return out, true
	}
	arr, is_arr := v.(json.Array)
	if !is_arr || len(arr) != 3 {
		fmt.eprintfln("scene config: %q must be a [x, y, z] array", key)
		return {}, false
	}
	for i in 0 ..< 3 {
		s, ok := parse_scalar_value(arr[i])
		if !ok {
			return {}, false
		}
		out[i] = s
	}
	return out, true
}

@(private = "file")
str_field :: proc(obj: json.Object, key: string, default: string) -> (string, bool) {
	v, found := obj[key]
	if !found {
		return default, true
	}
	s, is_str := v.(json.String)
	if !is_str {
		fmt.eprintfln("scene config: %q must be a string", key)
		return "", false
	}
	return s, true
}

@(private = "file")
material_spec_from :: proc(v: json.Value, context_key: string) -> (MaterialSpec, bool) {
	spec := MaterialSpec {
		kind = "lambertian",
	}
	obj, is_obj := v.(json.Object)
	if !is_obj {
		fmt.eprintfln("scene config: %s must be an object", context_key)
		return {}, false
	}
	kind, ok := str_field(obj, "kind", "lambertian")
	if !ok {
		return {}, false
	}
	spec.kind = kind
	if spec.albedo, ok = vec_field(obj, "albedo", {}); !ok {
		return {}, false
	}
	if spec.emission, ok = vec_field(obj, "emission", {}); !ok {
		return {}, false
	}
	if spec.fuzz, ok = scalar_field(obj, "fuzz", 0); !ok {
		return {}, false
	}
	if spec.refraction_index, ok = scalar_field(obj, "refraction_index", 0); !ok {
		return {}, false
	}
	return spec, true
}

material_type_from :: proc(kind: string) -> MaterialType {
	switch kind {
	case "metal":
		return .metal
	case "dielectric":
		return .dielectric
	case "diffuse_light":
		return .diffuse_light
	case "lambertian":
		return .lambertian
	case:
		fmt.eprintfln("scene config: unknown material kind %q, using lambertian", kind)
		return .lambertian
	}
}

// Sampling is where fixed-or-range values become concrete numbers.
build_material :: proc(spec: MaterialSpec) -> SceneMaterial {
	return SceneMaterial {
		kind = material_type_from(spec.kind),
		albedo = sample_vec(spec.albedo),
		fuzz = sample(spec.fuzz),
		refraction_index = sample(spec.refraction_index),
		emission = sample_vec(spec.emission),
	}
}

@(private = "file")
append_spheres_from :: proc(scene: ^Scene, arr: json.Array) -> bool {
	for item, idx in arr {
		obj, is_obj := item.(json.Object)
		if !is_obj {
			fmt.eprintfln("scene config: spheres[%d] must be an object", idx)
			return false
		}
		position, ok := vec_field(obj, "position", {})
		if !ok {
			return false
		}
		direction, dir_ok := vec_field(obj, "direction", {})
		if !dir_ok {
			return false
		}
		radius, rad_ok := scalar_field(obj, "radius", 0.5)
		if !rad_ok {
			return false
		}
		mat_value, has_mat := obj["material"]
		spec := MaterialSpec {
			kind = "lambertian",
		}
		if has_mat {
			spec, ok = material_spec_from(mat_value, fmt.tprintf("spheres[%d].material", idx))
			if !ok {
				return false
			}
		}
		append(
			&scene.objects,
			SceneObject {
				type = .sphere,
				position = sample_vec(position),
				direction = sample_vec(direction),
				radius = sample(radius),
				material = build_material(spec),
			},
		)
	}
	return true
}

@(private = "file")
append_quads_from :: proc(scene: ^Scene, arr: json.Array) -> bool {
	for item, idx in arr {
		obj, is_obj := item.(json.Object)
		if !is_obj {
			fmt.eprintfln("scene config: quads[%d] must be an object", idx)
			return false
		}
		corner, ok1 := vec_field(obj, "corner", {})
		edge_u, ok2 := vec_field(obj, "edge_u", {})
		edge_v, ok3 := vec_field(obj, "edge_v", {})
		if !ok1 || !ok2 || !ok3 {
			return false
		}
		mat_value, has_mat := obj["material"]
		spec := MaterialSpec {
			kind = "lambertian",
		}
		if has_mat {
			ok: bool
			spec, ok = material_spec_from(mat_value, fmt.tprintf("quads[%d].material", idx))
			if !ok {
				return false
			}
		}
		append(
			&scene.quads,
			SceneQuad {
				corner = sample_vec(corner),
				edge_u = sample_vec(edge_u),
				edge_v = sample_vec(edge_v),
				material = build_material(spec),
			},
		)
	}
	return true
}

@(private = "file")
append_cuboids_from :: proc(scene: ^Scene, arr: json.Array) -> bool {
	for item, idx in arr {
		obj, is_obj := item.(json.Object)
		if !is_obj {
			fmt.eprintfln("scene config: cuboids[%d] must be an object", idx)
			return false
		}
		a, ok1 := vec_field(obj, "a", {})
		b, ok2 := vec_field(obj, "b", {})
		offset, ok3 := vec_field(obj, "offset", {})
		rot, ok4 := scalar_field(obj, "rotation_deg", 0)
		if !ok1 || !ok2 || !ok3 || !ok4 {
			return false
		}
		mat_value, has_mat := obj["material"]
		spec := MaterialSpec {
			kind = "lambertian",
		}
		if has_mat {
			ok: bool
			spec, ok = material_spec_from(mat_value, fmt.tprintf("cuboids[%d].material", idx))
			if !ok {
				return false
			}
		}
		append_cuboid(
			scene,
			sample_vec(a),
			sample_vec(b),
			sample(rot),
			sample_vec(offset),
			build_material(spec),
		)
	}
	return true
}

@(private = "file")
grid_spec_from :: proc(v: json.Value) -> (GridSpec, bool) {
	spec: GridSpec
	obj, is_obj := v.(json.Object)
	if !is_obj {
		fmt.eprintfln("scene config: random_grid must be an object")
		return {}, false
	}
	radius, ok := scalar_field(obj, "grid_radius", 0)
	if !ok || radius.is_range {
		fmt.eprintfln("scene config: grid_radius must be a fixed integer")
		return {}, false
	}
	spec.grid_radius = int(radius.min)
	if spec.jitter, ok = vec_field(obj, "position_jitter", {}); !ok {
		return {}, false
	}
	if spec.direction, ok = vec_field(obj, "direction", {}); !ok {
		return {}, false
	}
	if spec.radius, ok = scalar_field(obj, "radius", 0.2); !ok {
		return {}, false
	}

	mat_value, has_mat := obj["material"]
	if !has_mat {
		fmt.eprintfln("scene config: random_grid.material is required")
		return {}, false
	}
	mat_obj, mat_is_obj := mat_value.(json.Object)
	if !mat_is_obj {
		fmt.eprintfln("scene config: random_grid.material must be an object")
		return {}, false
	}
	kinds_value, has_kinds := mat_obj["kinds"]
	kinds_arr, kinds_is_arr := kinds_value.(json.Array)
	if !has_kinds || !kinds_is_arr || len(kinds_arr) == 0 {
		fmt.eprintfln("scene config: random_grid.material.kinds must be a non-empty array")
		return {}, false
	}
	kinds := make([]string, len(kinds_arr))
	for k, i in kinds_arr {
		kind_str, is_str := k.(json.String)
		if !is_str {
			fmt.eprintfln("scene config: random_grid.material.kinds[%d] must be a string", i)
			return {}, false
		}
		kinds[i] = strings.clone(kind_str)
	}
	spec.kinds = kinds
	spec.templates = make(map[string]MaterialSpec)
	for kind in spec.kinds {
		tmpl_value, has_tmpl := mat_obj[kind]
		tmpl := MaterialSpec {
			kind = kind,
		}
		if has_tmpl {
			ok: bool
			tmpl, ok = material_spec_from(tmpl_value, fmt.tprintf("random_grid.material.%s", kind))
			if !ok {
				return {}, false
			}
			tmpl.kind = kind
		}
		spec.templates[kind] = tmpl
	}
	return spec, true
}

@(private = "file")
grid_spec_destroy :: proc(spec: ^GridSpec) {
	for kind in spec.kinds {
		delete(kind)
	}
	delete(spec.kinds)
	delete(spec.templates)
}

// Mirrors random_sphere: kind pick first, then material fields, then position,
// direction, radius — so the RNG draw order matches the code-built grid.
@(private = "file")
append_random_grid_from :: proc(scene: ^Scene, spec: GridSpec) {
	for i in -spec.grid_radius ..< spec.grid_radius {
		for j in -spec.grid_radius ..< spec.grid_radius {
			kind := spec.kinds[rand.int_max(len(spec.kinds))]
			material := build_material(spec.templates[kind])
			append(
				&scene.objects,
				SceneObject {
					type = .sphere,
					position = {
						f64(i) + sample(spec.jitter.x),
						sample(spec.jitter.y),
						f64(j) + sample(spec.jitter.z),
					},
					direction = sample_vec(spec.direction),
					radius = sample(spec.radius),
					material = material,
				},
			)
		}
	}
}

// loads path and materializes the whole scene. Returns ok=false on any
// malformed content; messages go to stderr with the offending key.
load_scene_json :: proc(path: string) -> (LoadedScene, bool) {
	loaded: LoadedScene

	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		fmt.eprintfln("scene config: cannot read %s (%v)", path, read_err)
		return {}, false
	}
	defer delete(data)

	root, parse_err := json.parse(data, .JSON5)
	if parse_err != .None {
		fmt.eprintfln("scene config: parse error in %s: %v", path, parse_err)
		return {}, false
	}
	// The tree is kept on success so the preview can save camera captures.
	keep_root := false
	defer if !keep_root {
		json.destroy_value(root)
	}

	root_obj, is_obj := root.(json.Object)
	if !is_obj {
		fmt.eprintfln("scene config: top level must be an object")
		return {}, false
	}

	name, ok := str_field(root_obj, "name", "scene")
	if !ok {
		return {}, false
	}

	// Seed before anything samples the RNG so ranges are reproducible.
	if seed_value, has_seed := root_obj["seed"]; has_seed {
		seed, seed_ok := parse_scalar_value(seed_value)
		if !seed_ok || seed.is_range {
			fmt.eprintfln("scene config: seed must be a fixed integer")
			return {}, false
		}
		rand.reset(u64(i64(seed.min)))
	}

	// --- render settings (all optional; defaults mirror raytracer.init) ---
	render := RenderTarget {
		width        = 1600,
		ratio        = 16.0 / 9.0,
		upscale      = 1,
		color_format = 4,
		threads      = 8,
		accelerator  = "bvh",
	}
	if render_value, has_render := root_obj["render"]; has_render {
		render_obj, render_is_obj := render_value.(json.Object)
		if !render_is_obj {
			fmt.eprintfln("scene config: render must be an object")
			return {}, false
		}
		width, ok1 := scalar_field(render_obj, "width", render.width)
		upscale, ok2 := scalar_field(render_obj, "upscale", render.upscale)
		format, ok3 := scalar_field(render_obj, "color_format", f64(render.color_format))
		threads, ok4 := scalar_field(render_obj, "threads", f64(render.threads))
		accel, ok5 := str_field(render_obj, "accelerator", render.accelerator)
		if !ok1 || !ok2 || !ok3 || !ok4 || !ok5 {
			return {}, false
		}
		render.width, render.upscale = width.min, upscale.min
		render.color_format = u8(format.min)
		render.threads = max(1, int(threads.min))
		render.accelerator = strings.clone(accel)
		if ratio_value, has_ratio := render_obj["ratio"]; has_ratio {
			ratio_arr, ratio_is_arr := ratio_value.(json.Array)
			if !ratio_is_arr || len(ratio_arr) != 2 {
				fmt.eprintfln("scene config: render.ratio must be [width, height]")
				return {}, false
			}
			num, ok_num := parse_scalar_value(ratio_arr[0])
			den, ok_den := parse_scalar_value(ratio_arr[1])
			if !ok_num || !ok_den || den.min == 0 {
				fmt.eprintfln("scene config: render.ratio must be two fixed numbers, height != 0")
				return {}, false
			}
			render.ratio = num.min / den.min
		}
	} else {
		render.accelerator = strings.clone(render.accelerator)
	}
	loaded.render = render

	// --- camera (required) ---
	camera_value, has_camera := root_obj["camera"]
	camera_obj, camera_is_obj := camera_value.(json.Object)
	if !has_camera || !camera_is_obj {
		fmt.eprintfln("scene config: camera block is required")
		return {}, false
	}
	position, okc1 := vec_field(camera_obj, "position", {})
	look_at, okc2 := vec_field(camera_obj, "look_at", {})
	vfov, okc3 := scalar_field(camera_obj, "vfov", 45)
	defocus, okc4 := scalar_field(camera_obj, "defocus_angle", 0)
	focus, okc5 := scalar_field(camera_obj, "focus_dist", 10)
	samples, okc6 := scalar_field(camera_obj, "samples", 25)
	max_depth, okc7 := scalar_field(camera_obj, "max_depth", 10)
	if !okc1 || !okc2 || !okc3 || !okc4 || !okc5 || !okc6 || !okc7 {
		return {}, false
	}
	camera := scene_camera(
		sample_vec(position),
		sample_vec(look_at),
		sample(vfov),
		sample(defocus),
		sample(focus),
		max(1, int(samples.min)),
		max(1, int(max_depth.min)),
	)
	camera.ratio = render.ratio

	// --- world content ---
	grid_count := 0
	grid_value, has_grid := root_obj["random_grid"]
	// NOTE: defer is block-scoped in Odin, so the grid spec is destroyed
	// explicitly after append_random_grid_from instead of via defer (which
	// would fire at the end of this if-block and free the kind strings early).
	grid: GridSpec
	if has_grid {
		grid_spec_ok: bool
		grid, grid_spec_ok = grid_spec_from(grid_value)
		if !grid_spec_ok {
			return {}, false
		}
		side := 2 * grid.grid_radius
		grid_count = side * side
	}
	spheres_count := 0
	if spheres_value, has := root_obj["spheres"]; has {
		spheres_count = len(spheres_value.(json.Array) or_else json.Array{})
	}

	scene := scene_with_camera(camera, spheres_count + grid_count + 1)
	scene.name = strings.clone(name)

	if spheres_value, has := root_obj["spheres"]; has {
		arr, arr_ok := spheres_value.(json.Array)
		if !arr_ok {
			fmt.eprintfln("scene config: spheres must be an array")
			return {}, false
		}
		if !append_spheres_from(&scene, arr) {
			return {}, false
		}
	}
	if quads_value, has := root_obj["quads"]; has {
		arr, arr_ok := quads_value.(json.Array)
		if !arr_ok {
			fmt.eprintfln("scene config: quads must be an array")
			return {}, false
		}
		if !append_quads_from(&scene, arr) {
			return {}, false
		}
	}
	if cuboids_value, has := root_obj["cuboids"]; has {
		arr, arr_ok := cuboids_value.(json.Array)
		if !arr_ok {
			fmt.eprintfln("scene config: cuboids must be an array")
			return {}, false
		}
		if !append_cuboids_from(&scene, arr) {
			return {}, false
		}
	}
	if has_grid {
		append_random_grid_from(&scene, grid)
		grid_spec_destroy(&grid)
	}

	loaded.config = ConfigState{path = strings.clone(path), root = root}
	keep_root = true
	loaded.scene = scene
	return loaded, true
}
