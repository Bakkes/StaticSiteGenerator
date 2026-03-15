package main

import "core:fmt"
import "core:os"
import "core:strings"
import zlib "vendor:zlib"

// ---------------------------------------------------------------------------
// Build Validation
// ---------------------------------------------------------------------------

MAX_GZIP_SIZE :: 14 * 1024 // 14kB — TCP slow start first window
GZIP_OVERHEAD :: 18        // gzip header (10) + trailer (8)

validate_output :: proc(config: Site_Config, allocator := context.allocator) -> bool {
	fmt.println("\nValidations:")
	all_ok := true
	validate_dir(config.output_dir, config.output_dir, &all_ok, allocator)
	if all_ok {
		fmt.println("  All passed!")
	} else {
		fmt.eprintln("  Validation FAILED!")
	}
	return all_ok
}

validate_dir :: proc(dir: string, root: string, ok: ^bool, allocator := context.allocator) {
	entries, err := os.read_all_directory_by_path(dir, allocator)
	if err != nil {
		return
	}

	for entry in entries {
		if entry.type == .Directory {
			validate_dir(entry.fullpath, root, ok, allocator)
			continue
		}

		if !strings.has_suffix(entry.name, ".html") &&
		   !strings.has_suffix(entry.name, ".css") &&
		   !strings.has_suffix(entry.name, ".xml") {
			continue
		}

		data, read_err := os.read_entire_file_from_path(entry.fullpath, allocator)
		if read_err != nil {
			continue
		}

		// Build relative display path: "articles/foo.html" instead of absolute
		display_path: string
		if idx := strings.last_index(entry.fullpath, root); idx >= 0 {
			display_path = entry.fullpath[idx + len(root):]
			display_path = strings.trim_left(display_path, "/")
		} else {
			display_path = entry.name
		}

		gz_size := zlib_compressed_size(data, allocator) + GZIP_OVERHEAD

		if gz_size > MAX_GZIP_SIZE {
			fmt.printfln("  FAIL  %s  (%d bytes gz, limit %d)", display_path, gz_size, MAX_GZIP_SIZE)
			ok^ = false
		} else {
			fmt.printfln("  OK    %s  (%d bytes gz)", display_path, gz_size)
		}
	}
}

zlib_compressed_size :: proc(data: []u8, allocator := context.allocator) -> int {
	if len(data) == 0 {
		return 0
	}

	bound := zlib.compressBound(cast(zlib.uLong)len(data))
	buf := make([]u8, bound, allocator)
	dest_len := cast(zlib.uLong)bound

	ret := zlib.compress(raw_data(buf), &dest_len, raw_data(data), cast(zlib.uLong)len(data))
	if ret != zlib.OK {
		return len(data)
	}

	return cast(int)dest_len
}
