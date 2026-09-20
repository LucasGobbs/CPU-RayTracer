package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

USAGE :: `usage: main [options] [config]

  options:
    --auto-render   render immediately when the editor opens
    --headless      render without opening the editor, then exit
    --runs=N        headless render repetitions (median reported), default 3

  config            scene JSON path, default scenes/complex.json
`

main :: proc() {
	config_path := "scenes/complex.json"
	auto_render := false
	headless := false
	run_count := 1

	for arg in os.args[1:] {
		if arg == "--auto-render" {
			auto_render = true
		} else if arg == "--headless" {
			headless = true
		} else if strings.has_prefix(arg, "--runs=") {
			n, ok_parsed := strconv.parse_int(arg[len("--runs="):])
			if !ok_parsed || n < 1 {
				fmt.eprintfln("main: --runs must be a positive integer, got %q", arg)
				os.exit(1)
			}
			run_count = n
		} else if arg == "--help" || arg == "-h" {
			fmt.print(USAGE)
			return
		} else if strings.has_prefix(arg, "--") {
			fmt.eprintfln("main: unknown option %q", arg)
			fmt.print(USAGE)
			os.exit(1)
		} else {
			config_path = arg
		}
	}

	if headless {
		headless_run(config_path, run_count)
		return
	}
	editor_run(config_path, auto_render)
}
