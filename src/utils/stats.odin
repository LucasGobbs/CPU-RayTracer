package utils

import "core:fmt"
import "core:slice"
import "core:time"

// Date-time slug that sorts chronologically as a filename prefix, e.g.
// "2026-09-19_14-38-29". Returned against context.temp_allocator.
render_datetime_slug :: proc() -> string {
	date_buf: [64]u8
	hms_buf: [64]u8
	now := time.now()
	date := time.to_string_yyyy_mm_dd(now, date_buf[:])
	hms := time.to_string_hms(now, hms_buf[:])
	return fmt.tprintf(
		"%s_%c%c-%c%c-%c%c",
		date,
		hms[0], hms[1],
		hms[3], hms[4],
		hms[6], hms[7],
	)
}

// Median of measured durations. Robust for noisy perf runs: one slow outlier
// does not move it, unlike a mean. Sorts a scratch copy; input untouched.
median_duration :: proc(times: []time.Duration) -> time.Duration {
	n := len(times)
	scratch := slice.clone(times)
	defer delete(scratch)
	slice.sort(scratch)

	mid := n / 2
	if n % 2 == 1 {
		return scratch[mid]
	}
	return scratch[mid - 1] + (scratch[mid] - scratch[mid - 1]) / 2
}
