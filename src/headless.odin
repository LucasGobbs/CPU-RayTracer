package main

import rayt "raytracer"
import collider "raytracer/collider"
import scene_data "scene"
import "utils"

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

RENDER_CSV :: "reports/renders.csv"
RENDER_CSV_HEADER :: "timestamp_ns,config,scene,grouping,width,height,samples,max_depth,upscale,color_format,threads,runs,median_ms,min_ms,max_ms,image_file\n"

// headless_report gathers everything written to one CSV row.
HeadlessReport :: struct {
	config:     string,
	scene_name: string,
	grouping:   collider.GroupingKind,
	width:      f64,
	height:     f64,
	samples:    int,
	max_depth:  int,
	upscale:    f64,
	color_fmt:  u8,
	threads:    int,
	runs:       int,
	median:     time.Duration,
	min_run:    time.Duration,
	max_run:    time.Duration,
	image_path: string,
}

headless_stats :: proc(durations: []time.Duration) -> (median, min_run, max_run: time.Duration) {
	median = utils.median_duration(durations)
	min_run, max_run = durations[0], durations[0]
	for d in durations {
		min_run = min(min_run, d)
		max_run = max(max_run, d)
	}
	return
}

headless_save_image :: proc(
	pixels: []u8,
	cam: rayt.Camera,
	scene_name: string,
	kind: collider.GroupingKind,
	elapsed: time.Duration,
) -> string {
	os.make_directory("rendered")
	filename := fmt.tprintf(
		"rendered/%s_%s_%v_render_%.2fms_%d.png",
		utils.render_datetime_slug(),
		scene_name,
		kind,
		time.duration_milliseconds(elapsed),
		time.to_unix_nanoseconds(time.now()),
	)
	filename_c := strings.clone_to_cstring(filename, context.temp_allocator)
	image := rl.Image {
		width   = c.int(cam.image_width),
		height  = c.int(cam.image_height),
		data    = raw_data(pixels),
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	if !rl.ExportImage(image, filename_c) {
		fmt.eprintln("headless: could not save render image")
		return ""
	}
	return strings.clone(filename)
}

headless_append_csv :: proc(r: HeadlessReport) -> bool {
	os.make_directory("reports")

	write_header := true
	if info, err := os.stat(RENDER_CSV, context.allocator); err == os.ERROR_NONE {
		write_header = info.size == 0
	}

	file, open_err := os.open(RENDER_CSV, {.Write, .Append, .Create})
	if open_err != os.ERROR_NONE {
		fmt.eprintln("headless: could not open", RENDER_CSV)
		return false
	}
	defer os.close(file)

	if write_header {
		if _, err := os.write_string(file, RENDER_CSV_HEADER); err != os.ERROR_NONE {
			fmt.eprintln("headless: could not write CSV header")
			return false
		}
	}

	row := fmt.tprintf(
		"%d,%s,%s,%v,%d,%d,%d,%d,%g,%d,%d,%d,%.2f,%.2f,%.2f,%s\n",
		time.to_unix_nanoseconds(time.now()),
		r.config,
		r.scene_name,
		r.grouping,
		int(r.width),
		int(r.height),
		r.samples,
		r.max_depth,
		r.upscale,
		r.color_fmt,
		r.threads,
		r.runs,
		time.duration_milliseconds(r.median),
		time.duration_milliseconds(r.min_run),
		time.duration_milliseconds(r.max_run),
		r.image_path,
	)
	if _, err := os.write_string(file, row); err != os.ERROR_NONE {
		fmt.eprintln("headless: could not write CSV row")
		return false
	}
	return true
}

headless_run :: proc(config_path: string, run_count: int) {
	report := HeadlessReport {
		config = strings.clone(config_path),
	}
	defer delete(report.config)
	defer if report.image_path != "" {delete(report.image_path)}

	loaded, ok := scene_data.load_scene_json(config_path)
	if !ok {
		fmt.eprintfln("headless: could not load scene config %q", config_path)
		os.exit(1)
	}
	defer scene_data.scene_destroy(&loaded.scene)

	render := loaded.render
	accelerator := collider.GroupingKind.BVH
	if render.accelerator == "linear" {
		accelerator = .Linear
	} else if render.accelerator != "bvh" {
		fmt.eprintfln("headless: unknown accelerator %q, using bvh", render.accelerator)
	}

	raytracer_data := rayt.init(
		image_upscale = render.upscale,
		image_width = render.width,
		ratio = loaded.scene.camera.ratio,
		color_format = render.color_format,
	)
	params, world := rayt.load_from_scene(&loaded.scene)
	defer rayt.world_destroy(&world)
	collider.grouping_build(&world.space, accelerator)
	cam := rayt.build_camera(&params, raytracer_data)

	pixels := make([]u8, raytracer_data.buffer_size)
	defer delete(pixels)

	run_total := max(run_count, 1)
	durations := make([]time.Duration, run_total)
	defer delete(durations)

	for run in 0 ..< run_total {
		start := time.tick_now()
		rayt.renderer_render_threaded(raytracer_data, cam, &world, pixels, render.threads)
		durations[run] = time.tick_since(start)
	}

	report.runs = run_total
	report.median, report.min_run, report.max_run = headless_stats(durations)

	grouping := collider.grouping_kind(world.space.grouping)
	report.scene_name = loaded.scene.name
	report.grouping = grouping
	report.width = cam.image_width
	report.height = cam.image_height
	report.samples = cam.samples
	report.max_depth = cam.max_depth
	report.upscale = raytracer_data.image_upscale
	report.color_fmt = raytracer_data.color_format
	report.threads = render.threads

	report.image_path = headless_save_image(
		pixels,
		cam,
		loaded.scene.name,
		grouping,
		report.median,
	)
	headless_append_csv(report)

	fmt.printfln(
		"scene=%s grouping=%v %gx%g samples=%d depth=%d threads=%d runs=%d",
		report.scene_name,
		report.grouping,
		report.width,
		report.height,
		report.samples,
		report.max_depth,
		report.threads,
		report.runs,
	)
	fmt.printfln(
		"median=%.2fms min=%.2fms max=%.2fms",
		time.duration_milliseconds(report.median),
		time.duration_milliseconds(report.min_run),
		time.duration_milliseconds(report.max_run),
	)
	if report.image_path != "" {fmt.printfln("image=%s", report.image_path)}
	fmt.printfln("report=%s", RENDER_CSV)
}
