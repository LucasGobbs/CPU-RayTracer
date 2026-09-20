package main
import "core:fmt"
import "core:log"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:testing"

CliApp :: struct {
	input:    []string,
	args:     map[string]CliArg,
	commands: map[string]string,
}
CliArgValue :: union {
	bool,
	int,
	f64,
	string,
}
CliArg :: struct {
	usage:   string,
	default: CliArgValue,
}


cli_create :: proc(input: []string) -> CliApp {
	cli_app := CliApp {
		input    = input,
		args     = make(map[string]CliArg),
		commands = make(map[string]string),
	}
	return cli_app
}

cli_destroy :: proc(cli_app: ^CliApp) {
	delete(cli_app.args)
	delete(cli_app.commands)
}

cli_add_bool_arg :: proc(app: ^CliApp, arg: string, usage: string, default: bool = false) {
	app.args[arg] = CliArg {
		usage   = usage,
		default = default,
	}
}
cli_add_int_arg :: proc(app: ^CliApp, arg: string, usage: string, default: int = 0) {
	app.args[arg] = CliArg {
		usage   = usage,
		default = default,
	}
}
cli_add_string_arg :: proc(app: ^CliApp, arg: string, usage: string, default: string = "") {
	app.args[arg] = CliArg {
		usage   = usage,
		default = default,
	}
}

cli_add_command :: proc(app: ^CliApp, command: string, usage: string) {
	app.commands[command] = usage
}

cli_check_command :: proc(app: ^CliApp, command: string) -> bool {
	if _, ok := app.commands[command]; !ok {
		log.error(fmt.tprintf("Command (%s) was not defined inside CliApp", command))
		os.exit(1)
	}

	for input in app.input {
		if input == command do return true
	}

	return false
}

cli_check_bool_arg :: proc(app: ^CliApp, arg: string) -> bool {
	arg_definition, ok := app.args[arg]
	if !ok {
		log.error(fmt.tprintf("Argument (%s) was not defined inside CliApp", arg))
		os.exit(1)
	}

	input_arg := fmt.tprintf("--%s", arg)
	for input in app.input {
		if input == input_arg do return true
	}


	if bool_default_value, ok := arg_definition.default.(bool); ok do return bool_default_value

	return false
}

cli_print_help :: proc(app: ^CliApp) {
	command_names := make([dynamic]string, 0, len(app.commands))
	defer delete(command_names)
	for name in app.commands {
		append(&command_names, name)
	}
	slice.sort(command_names[:])

	if len(command_names) > 0 {
		fmt.println("commands:")
		for name in command_names {
			fmt.printfln("\t%s\t%s", name, app.commands[name])
		}
	}

	arg_names := make([dynamic]string, 0, len(app.args))
	defer delete(arg_names)
	for name in app.args {
		append(&arg_names, name)
	}
	slice.sort(arg_names[:])

	fmt.println("options:")
	for name in arg_names {
		arg := app.args[name]
		#partial switch default_value in arg.default {
		case int:
			fmt.printfln("\t--%s=N\t%s (default %d)", name, arg.usage, default_value)
		case string:
			if len(default_value) > 0 {
				fmt.printfln("\t--%s=S\t%s (default %q)", name, arg.usage, default_value)
			} else {
				fmt.printfln("\t--%s=S\t%s", name, arg.usage)
			}
		case:
			fmt.printfln("\t--%s\t%s", name, arg.usage)
		}
	}
	fmt.println("\t-h, --help\tprint this help and exit")
}

cli_check_help :: proc(app: ^CliApp) -> bool {
	for input in app.input {
		if input == "--help" || input == "-h" {
			cli_print_help(app)
			return true
		}
	}

	return false
}

cli_check_int_arg :: proc(app: ^CliApp, arg: string) -> int {
	arg_definition, ok := app.args[arg]
	if !ok {
		log.error(fmt.tprintf("Argument (%s) was not defined inside CliApp", arg))
		return 0
	}

	arg_formatted := fmt.tprintf("--%s=", arg)
	for input in app.input {
		if strings.has_prefix(input, arg_formatted) {
			raw_value := input[len(arg_formatted):]
			int_value, ok := strconv.parse_int(raw_value)
			if !ok {
				log.error(fmt.printfln("Value %s is not a valid integer", raw_value))
				return 0
			}

			return int_value
		}
	}

	if int_default_value, ok := arg_definition.default.(int); ok do return int_default_value

	return 0
}

cli_check_string_arg :: proc(app: ^CliApp, arg: string) -> string {
	arg_definition, ok := app.args[arg]
	if !ok {
		log.error(fmt.tprintf("Argument (%s) was not defined inside CliApp", arg))
		os.exit(1)
	}

	arg_formatted := fmt.tprintf("--%s=", arg)
	for input in app.input {
		if strings.has_prefix(input, arg_formatted) {
			return input[len(arg_formatted):]
		}
	}

	if string_default_value, ok := arg_definition.default.(string); ok do return string_default_value

	return ""
}

@(test)
test_cli :: proc(t: ^testing.T) {
	test1: []string = {"--test-bool", "--test-int=5", "--test-string=\"alo\""}
	cli_app := cli_create(test1)
	cli_add_bool_arg(&cli_app, "test-bool", "test bool")
	cli_add_bool_arg(&cli_app, "test-int", "test integer")

	// Successfull
	testing.expect_value(t, cli_check_bool_arg(&cli_app, "test-bool"), true)
	testing.expect_value(t, cli_check_int_arg(&cli_app, "test-int"), 5)
	cli_destroy(&cli_app)

	// String
	string_input: []string = {"--test-string=alo"}
	string_app := cli_create(string_input)
	cli_add_string_arg(&string_app, "test-string", "test string")
	cli_add_string_arg(&string_app, "missing-string", "missing string", "fallback")
	testing.expect_value(t, cli_check_string_arg(&string_app, "test-string"), "alo")
	testing.expect_value(t, cli_check_string_arg(&string_app, "missing-string"), "fallback")
	cli_destroy(&string_app)

	// Command
	command_input: []string = {"render", "--test-bool"}
	command_app := cli_create(command_input)
	cli_add_command(&command_app, "render", "render the scene")
	cli_add_command(&command_app, "update", "update the scene")
	cli_add_bool_arg(&command_app, "test-bool", "test bool")
	testing.expect_value(t, cli_check_command(&command_app, "render"), true)
	testing.expect_value(t, cli_check_command(&command_app, "update"), false)
	cli_destroy(&command_app)

	// Help
	help_inputs: [][]string = {{"--help"}, {"-h"}, {"--test-bool", "--help"}}
	for help_input in help_inputs {
		help_app := cli_create(help_input)
		cli_add_command(&help_app, "render", "render the scene")
		cli_add_bool_arg(&help_app, "test-bool", "test bool")
		cli_add_int_arg(&help_app, "test-int", "test integer", 5)
		cli_add_string_arg(&help_app, "test-string", "test string", "fallback")
		testing.expect_value(t, cli_check_help(&help_app), true)
		cli_destroy(&help_app)
	}

	no_help_input: []string = {"--test-bool"}
	no_help_app := cli_create(no_help_input)
	cli_add_bool_arg(&no_help_app, "test-bool", "test bool")
	testing.expect_value(t, cli_check_help(&no_help_app), false)
	cli_destroy(&no_help_app)
}


// for arg in os.args[1:] {
// 	if arg == "--auto-render" {
// 		auto_render = true
// 	} else if arg == "--headless" {
// 		headless = true
// 	} else if strings.has_prefix(arg, "--runs=") {
// 		n, ok_parsed := strconv.parse_int(arg[len("--runs="):])
// 		if !ok_parsed || n < 1 {
// 			fmt.eprintfln("main: --runs must be a positive integer, got %q", arg)
// 			os.exit(1)
// 		}
// 		run_count = n
// 	} else if arg == "--help" || arg == "-h" {
// 		fmt.print(USAGE)
// 		return
// 	} else if strings.has_prefix(arg, "--") {
// 		fmt.eprintfln("main: unknown option %q", arg)
// 		fmt.print(USAGE)
// 		os.exit(1)
// 	} else {
// 		config_path = arg
// 	}
// }
