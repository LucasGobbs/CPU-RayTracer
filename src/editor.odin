package main

import "core:c"
import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

import rayt "raytracer"
import collider "raytracer/collider"
import scene_data "scene"
import "utils"
import rl "vendor:raylib"

EDITOR_SIDEBAR_WIDTH :: 360

Editor_State :: struct {
	loaded:                scene_data.LoadedScene,
	has_scene:             bool,
	config_path:           string,
	params:                rayt.CamParams,
	raytracer_data:        rayt.RaytracerParams,
	world:                 rayt.World,
	cam:                   rayt.Camera,
	fly:                   rl.Camera3D,
	mouse_captured:        bool,
	pixels:                []u8,
	scene_rt:              rl.RenderTexture,
	render_tex:            rl.Texture2D,
	has_render:            bool,
	show_render:           bool,
	render_ms:             f64,
	show_bounds:           bool,
	bounds_depth:          int,
	debug_ray_active:      bool,
	debug_ray:             collider.Ray,
	debug_hit_nodes:       [dynamic]int,
	debug_selected_active: bool,
	debug_selected_node:   int,
	debug_selected_depth:  int,
	debug_selected_t:      f64,
	debug_object_ids:      [dynamic]int,
	scene_files:           [dynamic]cstring,
	load_error:            string,
	tab:                   c.int,
	frames:                int,
	auto_render:           bool,
}

Bvh_Stats :: struct {
	height:         int,
	nodes:          int,
	leaves:         int,
	internal_nodes: int,
}

editor_bvh_stats_walk :: proc(nodes: []collider.BvhNode, index, depth: int, stats: ^Bvh_Stats) {
	if index < 0 {return}
	node := nodes[index]
	stats.height = max(stats.height, depth + 1)
	if node.count > 0 {
		stats.leaves += 1
		return
	}
	stats.internal_nodes += 1
	editor_bvh_stats_walk(nodes, node.left, depth + 1, stats)
	editor_bvh_stats_walk(nodes, node.right, depth + 1, stats)
}

editor_bvh_stats :: proc(state: ^Editor_State) -> Bvh_Stats {
	stats: Bvh_Stats
	switch grouping in state.world.space.grouping {
	case collider.Bvh:
		stats.nodes = len(grouping.nodes)
		if stats.nodes > 0 {
			editor_bvh_stats_walk(grouping.nodes[:], 0, 0, &stats)
		}
	case collider.LinearGrouping:
	}
	return stats
}

editor_clear_bvh_inspection :: proc(state: ^Editor_State) {
	clear(&state.debug_hit_nodes)
	clear(&state.debug_object_ids)
	state.debug_ray_active = false
	state.debug_selected_active = false
	state.debug_selected_node = -1
	state.debug_selected_depth = -1
	state.debug_selected_t = max(f64)
}

editor_reset_bvh_debug :: proc(state: ^Editor_State) {
	editor_clear_bvh_inspection(state)
	stats := editor_bvh_stats(state)
	state.bounds_depth = max(stats.height - 1, 0)
}

editor_ray_aabb_near :: proc(box: collider.Aabb, ray: collider.Ray) -> (f64, bool) {
	tmin, tmax := 0.001, max(f64)
	for axis in 0 ..< 3 {
		interval := collider.aabb_axis_interval(box, axis)
		o := ray.origin[axis]
		d := ray.direction[axis]
		if abs(d) < 1e-12 {
			if o < interval.min || o > interval.max {return 0, false}
			continue
		}
		a, b := (interval.min - o) / d, (interval.max - o) / d
		if a > b {a, b = b, a}
		tmin = max(tmin, a)
		tmax = min(tmax, b)
		if tmax <= tmin {return 0, false}
	}
	return tmin, true
}

editor_trace_bvh_node :: proc(
	state: ^Editor_State,
	nodes: []collider.BvhNode,
	index, depth: int,
	ray: collider.Ray,
) {
	if index < 0 || depth > state.bounds_depth {return}
	node := nodes[index]
	near, hit := editor_ray_aabb_near(node.box, ray)
	if !hit {return}
	append(&state.debug_hit_nodes, index)
	if !state.debug_selected_active ||
	   depth > state.debug_selected_depth ||
	   (depth == state.debug_selected_depth && near < state.debug_selected_t) {
		state.debug_selected_active = true
		state.debug_selected_node = index
		state.debug_selected_depth = depth
		state.debug_selected_t = near
	}
	if node.count == 0 && depth < state.bounds_depth {
		editor_trace_bvh_node(state, nodes, node.left, depth + 1, ray)
		editor_trace_bvh_node(state, nodes, node.right, depth + 1, ray)
	}
}

editor_collect_bvh_objects :: proc(
	nodes: []collider.BvhNode,
	indices: []int,
	index: int,
	objects: ^[dynamic]int,
) {
	if index < 0 {return}
	node := nodes[index]
	if node.count > 0 {
		for i in node.start ..< node.start + node.count {
			append(objects, indices[i])
		}
		return
	}
	editor_collect_bvh_objects(nodes, indices, node.left, objects)
	editor_collect_bvh_objects(nodes, indices, node.right, objects)
}

editor_inspect_bounds :: proc(state: ^Editor_State, viewport_pos: rl.Vector2) {
	editor_clear_bvh_inspection(state)
	switch grouping in state.world.space.grouping {
	case collider.Bvh:
		if len(grouping.nodes) == 0 {return}
		world_ray := rl.GetScreenToWorldRayEx(
			viewport_pos,
			state.fly,
			rl.GetScreenWidth() - EDITOR_SIDEBAR_WIDTH,
			rl.GetScreenHeight(),
		)
		state.debug_ray = {
			origin    = {
				f64(world_ray.position.x),
				f64(world_ray.position.y),
				f64(world_ray.position.z),
			},
			direction = {
				f64(world_ray.direction.x),
				f64(world_ray.direction.y),
				f64(world_ray.direction.z),
			},
		}
		state.debug_ray_active = true
		editor_trace_bvh_node(state, grouping.nodes[:], 0, 0, state.debug_ray)
		if state.debug_selected_active {
			editor_collect_bvh_objects(
				grouping.nodes[:],
				grouping.indices[:],
				state.debug_selected_node,
				&state.debug_object_ids,
			)
		}
		fmt.printfln(
			"BVH ray: boxes=%d selected_depth=%d objects=%d",
			len(state.debug_hit_nodes),
			state.debug_selected_depth,
			len(state.debug_object_ids),
		)
		fmt.println("BVH objects:", state.debug_object_ids[:])
	case collider.LinearGrouping:
	}
}

Editor_Action :: struct {
	render:                  bool,
	render_settings_changed: bool,
	camera_changed:          bool,
	reset_view:              bool,
	capture_view:            bool,
	toggle_grouping:         bool,
	toggle_bounds:           bool,
	show_preview:            bool,
	show_render:             bool,
	scene_path:              string,
}

editor_fly_from_camera :: proc(cam: rayt.Camera, vfov: f64) -> rl.Camera3D {
	return {
		position = {f32(cam.position.x), f32(cam.position.y), f32(cam.position.z)},
		target = {f32(cam.look_at.x), f32(cam.look_at.y), f32(cam.look_at.z)},
		up = {0, 1, 0},
		fovy = f32(vfov),
		projection = .PERSPECTIVE,
	}
}

editor_reset_view :: proc(state: ^Editor_State) {
	state.cam = rayt.build_camera(&state.params, state.raytracer_data)
	state.fly = editor_fly_from_camera(state.cam, state.params.vfov)
}

editor_rebuild_render_params :: proc(state: ^Editor_State) {
	state.params.ratio = state.loaded.render.ratio
	state.loaded.scene.camera.ratio = state.loaded.render.ratio
	state.raytracer_data = rayt.init(
		image_upscale = state.loaded.render.upscale,
		image_width = state.loaded.render.width,
		ratio = state.loaded.render.ratio,
		color_format = state.loaded.render.color_format,
	)
	if state.pixels != nil {delete(state.pixels)}
	state.pixels = make([]u8, state.raytracer_data.buffer_size)
	if state.has_render {
		rl.UnloadTexture(state.render_tex)
		state.has_render = false
		state.show_render = false
	}
	editor_reset_view(state)
}

editor_destroy_scene :: proc(state: ^Editor_State) {
	if !state.has_scene {return}
	rayt.world_destroy(&state.world)
	scene_data.scene_destroy(&state.loaded.scene)
	scene_data.config_state_destroy(&state.loaded.config)
	state.has_scene = false
}

editor_load_scene :: proc(state: ^Editor_State, path: string) -> bool {
	loaded, ok := scene_data.load_scene_json(path)
	if !ok {
		if state.load_error != "" {delete(state.load_error)}
		state.load_error = strings.clone(path)
		return false
	}

	editor_destroy_scene(state)
	if state.config_path != "" {delete(state.config_path)}
	if state.pixels != nil {delete(state.pixels)}
	if state.has_render {
		rl.UnloadTexture(state.render_tex)
		state.has_render = false
		state.show_render = false
	}

	state.loaded = loaded
	state.has_scene = true
	state.config_path = strings.clone(path)
	if state.load_error != "" {
		delete(state.load_error)
		state.load_error = ""
	}

	render := loaded.render
	accelerator := collider.GroupingKind.BVH
	if render.accelerator == "linear" {
		accelerator = .Linear
	} else if render.accelerator != "bvh" {
		fmt.eprintfln("unknown accelerator %q, using bvh", render.accelerator)
	}
	state.raytracer_data = rayt.init(
		image_upscale = render.upscale,
		image_width = render.width,
		ratio = loaded.scene.camera.ratio,
		color_format = render.color_format,
	)
	state.params, state.world = rayt.load_from_scene(&loaded.scene)
	collider.grouping_build(&state.world.space, accelerator)
	editor_reset_bvh_debug(state)
	state.pixels = make([]u8, state.raytracer_data.buffer_size)
	editor_reset_view(state)
	return true
}

editor_scan_scenes :: proc(state: ^Editor_State) {
	for path in state.scene_files {delete(path)}
	clear(&state.scene_files)
	infos, err := os.read_directory_by_path("scenes", -1, context.allocator)
	if err != nil {return}
	defer os.file_info_slice_delete(infos, context.allocator)
	for info in infos {
		if info.type != .Regular || filepath.ext(info.name) != ".json" {continue}
		append(&state.scene_files, fmt.caprintf("scenes/%s", info.name))
	}
}

editor_capture_pose :: proc(state: ^Editor_State) {
	state.params.position = rayt.Point3 {
		f64(state.fly.position.x),
		f64(state.fly.position.y),
		f64(state.fly.position.z),
	}
	state.params.look_at = rayt.Point3 {
		f64(state.fly.target.x),
		f64(state.fly.target.y),
		f64(state.fly.target.z),
	}
	state.params.vfov = f64(state.fly.fovy)
	state.cam = rayt.build_camera(&state.params, state.raytracer_data)
	path, ok := scene_data.save_camera_capture(
		&state.loaded.config,
		[3]f64{f64(state.fly.position.x), f64(state.fly.position.y), f64(state.fly.position.z)},
		[3]f64{f64(state.fly.target.x), f64(state.fly.target.y), f64(state.fly.target.z)},
		f64(state.fly.fovy),
	)
	if ok {
		fmt.println("capture written:", path)
		delete(path)
	}
}

editor_cycle_grouping :: proc(state: ^Editor_State) {
	kind := collider.grouping_kind(state.world.space.grouping)
	next := collider.grouping_kind_next(kind)
	start := time.tick_now()
	collider.grouping_build(&state.world.space, next)
	editor_reset_bvh_debug(state)
	fmt.println("grouping:", next, "- built in", time.tick_since(start))
}

editor_release_mouse :: proc(state: ^Editor_State) {
	if !state.mouse_captured {return}
	rl.EnableCursor()
	state.mouse_captured = false
	fmt.println("mouse released")
}

editor_update_fly_camera :: proc(state: ^Editor_State) {
	if state.show_render {
		editor_release_mouse(state)
		return
	}
	if state.mouse_captured && (rl.IsKeyPressed(.ESCAPE) || !rl.IsWindowFocused()) {
		editor_release_mouse(state)
		return
	}
	if state.show_bounds && rl.IsMouseButtonPressed(.RIGHT) {
		viewport_width := rl.GetScreenWidth() - EDITOR_SIDEBAR_WIDTH
		if state.mouse_captured {
			editor_inspect_bounds(
				state,
				{f32(viewport_width) * 0.5, f32(rl.GetScreenHeight()) * 0.5},
			)
		} else if rl.GetMouseX() >= EDITOR_SIDEBAR_WIDTH {
			editor_inspect_bounds(
				state,
				{f32(rl.GetMouseX() - EDITOR_SIDEBAR_WIDTH), f32(rl.GetMouseY())},
			)
		}
	}
	if !state.mouse_captured {
		if rl.GetMouseX() >= EDITOR_SIDEBAR_WIDTH && rl.IsMouseButtonPressed(.LEFT) {
			state.mouse_captured = true
			rl.DisableCursor()
			fmt.println("mouse captured (ESC to release)")
		}
		return
	}

	dt := rl.GetFrameTime()
	shift := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
	speed: f32 = 12 if shift else 3
	fwd := state.fly.target - state.fly.position
	fwd_len := math.sqrt(fwd.x * fwd.x + fwd.y * fwd.y + fwd.z * fwd.z)
	if fwd_len > 0 {fwd /= fwd_len}
	right := rl.Vector3{-fwd.z, 0, fwd.x}
	move: rl.Vector3
	if rl.IsKeyDown(.W) do move += fwd
	if rl.IsKeyDown(.S) do move -= fwd
	if rl.IsKeyDown(.D) do move += right
	if rl.IsKeyDown(.A) do move -= right
	if rl.IsKeyDown(.SPACE) do move += {0, 1, 0}
	if rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL) do move -= {0, 1, 0}
	move_len := math.sqrt(move.x * move.x + move.y * move.y + move.z * move.z)
	if move_len > 0 {
		move /= move_len
		state.fly.position += move * speed * dt
		state.fly.target += move * speed * dt
	}

	md := rl.GetMouseDelta()
	sens: f32 = 0.003
	distance := rl.Vector3Length(state.fly.target - state.fly.position)
	forward := rl.Vector3Normalize(state.fly.target - state.fly.position)
	world_up := rl.Vector3{0, 1, 0}

	// Positive mouse X means look right; in raylib's right-handed world that
	// is a negative rotation around +Y.
	yaw := rl.QuaternionFromAxisAngle(world_up, -md.x * sens)
	forward = rl.Vector3Normalize(rl.Vector3RotateByQuaternion(forward, yaw))

	// Positive mouse Y means look down. Pitch around the camera's current
	// local-right axis so yaw never changes what "up/down" means.
	right_axis := rl.Vector3Normalize(rl.Vector3CrossProduct(forward, world_up))
	pitch := rl.QuaternionFromAxisAngle(right_axis, -md.y * sens)
	candidate := rl.Vector3Normalize(rl.Vector3RotateByQuaternion(forward, pitch))
	if abs(rl.Vector3DotProduct(candidate, world_up)) < 0.995 {
		forward = candidate
	}
	state.fly.target = state.fly.position + forward * distance

	wheel := rl.GetMouseWheelMove()
	if wheel != 0 {state.fly.fovy = clamp(state.fly.fovy - wheel * 2, 1, 120)}
}

editor_save_render :: proc(state: ^Editor_State, elapsed: time.Duration) {
	filename := fmt.caprintf(
		"rendered/%s_%s_%v_render_%.2fms_%d.png",
		utils.render_datetime_slug(),
		state.loaded.scene.name,
		collider.grouping_kind(state.world.space.grouping),
		time.duration_milliseconds(elapsed),
		time.to_unix_nanoseconds(time.now()),
	)
	defer delete(filename)
	image := rl.Image {
		data    = raw_data(state.pixels),
		width   = c.int(state.cam.image_width),
		height  = c.int(state.cam.image_height),
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	if rl.ExportImage(image, filename) {
		fmt.println("Saved render:", filename)
	} else {
		fmt.println("Could not save render:", filename)
	}
	if state.has_render {rl.UnloadTexture(state.render_tex)}
	state.render_tex = rl.LoadTextureFromImage(image)
	state.has_render = true
	state.show_render = true
}

editor_raytrace :: proc(state: ^Editor_State, amount := 2) {
	rl.BeginDrawing()
	rl.ClearBackground(rl.Color{25, 25, 35, 255})
	rl.DrawText("Rendering...", 24, 24, 26, rl.ORANGE)
	rl.EndDrawing()

	run_count := max(amount, 1)
	runs := make([]time.Duration, run_count, context.temp_allocator)
	for run in 0 ..< run_count {
		start := time.tick_now()
		rayt.renderer_render_threaded(
			state.raytracer_data,
			state.cam,
			&state.world,
			state.pixels,
			state.loaded.render.threads,
		)
		runs[run] = time.tick_since(start)
	}
	elapsed := utils.median_duration(runs)
	state.render_ms = time.duration_milliseconds(elapsed)
	editor_save_render(state, elapsed)
}

editor_apply_action :: proc(state: ^Editor_State, action: Editor_Action) {
	if action.render_settings_changed {editor_rebuild_render_params(state)}
	if action.camera_changed {editor_reset_view(state)}
	if action.reset_view {editor_reset_view(state)}
	if action.capture_view {editor_capture_pose(state)}
	if action.toggle_grouping {editor_cycle_grouping(state)}
	if action.toggle_bounds {
		state.show_bounds = !state.show_bounds
		if !state.show_bounds {editor_clear_bvh_inspection(state)}
	}
	if action.show_preview {state.show_render = false}
	if action.show_render && state.has_render {
		editor_release_mouse(state)
		state.show_render = true
	}
	if action.scene_path != "" && action.scene_path != state.config_path {
		editor_load_scene(state, action.scene_path)
	}
	if action.render {
		editor_release_mouse(state)
		editor_raytrace(state)
	}
}

editor_free :: proc(state: ^Editor_State) {
	editor_release_mouse(state)
	if state.has_render {rl.UnloadTexture(state.render_tex)}
	if state.scene_rt.id != 0 {rl.UnloadRenderTexture(state.scene_rt)}
	if state.pixels != nil {delete(state.pixels)}
	for path in state.scene_files {delete(path)}
	delete(state.scene_files)
	delete(state.debug_hit_nodes)
	delete(state.debug_object_ids)
	if state.config_path != "" {delete(state.config_path)}
	if state.load_error != "" {delete(state.load_error)}
	editor_destroy_scene(state)
}

editor_run :: proc(config_path := "scenes/complex.json", auto_render := false) {
	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(1300, 950, "Odin Raytracer")
	rl.SetExitKey(.KEY_NULL)
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	state := Editor_State {
		auto_render = auto_render,
	}
	if !editor_load_scene(&state, config_path) {return}
	defer editor_free(&state)
	editor_scan_scenes(&state)
	state.scene_rt = rl.LoadRenderTexture(64, 64)

	for !rl.WindowShouldClose() {
		state.frames += 1
		editor_update_fly_camera(&state)
		keyboard := Editor_Action{}
		if rl.IsKeyPressed(.ENTER) {keyboard.render = true}
		if rl.IsKeyPressed(.C) {keyboard.capture_view = true}
		if rl.IsKeyPressed(.G) {keyboard.toggle_grouping = true}
		if rl.IsKeyPressed(.BACKSPACE) {keyboard.show_preview = true}
		if state.auto_render && state.frames >= 5 {
			state.auto_render = false
			keyboard.render = true
		}
		editor_apply_action(&state, keyboard)

		if !state.show_render {editor_draw_scene_rt(&state)}
		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{18, 20, 27, 255})
		editor_draw_main(&state)
		action := editor_draw_sidebar(&state)
		rl.EndDrawing()
		editor_apply_action(&state, action)
	}
}
