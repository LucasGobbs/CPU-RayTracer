package main

import "core:os"

main :: proc() {
	cli_app := cli_create(os.args[1:])
	defer cli_destroy(&cli_app)

	cli_add_bool_arg(&cli_app, "auto-render", "render immediately when the editor opens")
	cli_add_bool_arg(&cli_app, "headless", "render without opening the editor, then exit")
	cli_add_int_arg(&cli_app, "runs", "headless render repetitions (median reported)", 3)
	cli_add_string_arg(&cli_app, "path", "scene file path", "scenes/complex.json")
	if cli_check_help(&cli_app) do return

	auto_render := cli_check_bool_arg(&cli_app, "auto-render")
	headless := cli_check_bool_arg(&cli_app, "headless")
	run_count := cli_check_int_arg(&cli_app, "runs")
	config_path := cli_check_string_arg(&cli_app, "path")


	if headless {
		headless_run(config_path, run_count)
		return
	}
	editor_run(config_path, auto_render)
}
