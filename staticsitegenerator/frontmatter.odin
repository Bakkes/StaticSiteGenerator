package main

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:time"

// Split a markdown file into frontmatter text and body text.
// Frontmatter is delimited by --- lines at the top of the file.
// Returns slices into source — no allocations.
split_frontmatter :: proc(source: string) -> (fm_text: string, body: string) {
	first_nl := strings.index_byte(source, '\n')
	if first_nl < 0 || strings.trim_space(source[:first_nl]) != "---" {
		return "", source
	}

	// Search for closing --- line
	rest := source[first_nl + 1:]
	offset := 0
	for offset < len(rest) {
		nl := strings.index_byte(rest[offset:], '\n')
		end := offset + nl if nl >= 0 else len(rest)
		if strings.trim_space(rest[offset:end]) == "---" {
			fm_text = rest[:offset]
			if len(fm_text) > 0 && fm_text[len(fm_text) - 1] == '\n' {
				fm_text = fm_text[:len(fm_text) - 1]
			}
			body = rest[end + 1:] if end < len(rest) else ""
			return
		}
		if nl < 0 { break }
		offset = end + 1
	}

	return "", source
}

// Split a "key: value" YAML line into key and value strings.
split_yaml_line :: proc(line: string) -> (key, value: string, ok: bool) {
	colon := strings.index_byte(line, ':')
	if colon < 0 {
		return "", "", false
	}
	return strings.trim_space(line[:colon]), strings.trim_space(line[colon + 1:]), true
}

// Parse simple YAML-style key: value pairs from frontmatter text.
parse_frontmatter :: proc(fm_text: string, allocator := context.allocator) -> Frontmatter {
	fm := Frontmatter{
		tags = make([dynamic]string, allocator),
	}

	if len(fm_text) == 0 {
		return fm
	}

	lines := strings.split_lines(fm_text, allocator)
	for line in lines {
		key, value, ok := split_yaml_line(line)
		if !ok {
			continue
		}

		switch key {
		case "title":
			fm.title = value
		case "author":
			fm.author = value
		case "date":
			fm.date = value
		case "modified":
			fm.modified = value
		case "tags":
			fm.tags = parse_tags(value, allocator)
		case "priority":
			fm.priority = parse_int_simple(value)
		case "description":
			fm.description = value
		case "toc":
			fm.toc = value == "true"
		case "draft":
			fm.draft = value == "true"
		case "series":
			fm.series = value
		case "series_part":
			fm.series_part = parse_int_simple(value)
		}
	}

	return fm
}

// Parse tags from "[a, b, c]" syntax.
parse_tags :: proc(value: string, allocator := context.allocator) -> [dynamic]string {
	tags := make([dynamic]string, allocator)
	s := strings.trim_space(value)

	// Strip brackets
	if len(s) >= 2 && s[0] == '[' && s[len(s) - 1] == ']' {
		s = s[1:len(s) - 1]
	}

	parts := strings.split(s, ",", allocator)
	for part in parts {
		t := strings.trim_space(part)
		if len(t) > 0 {
			append(&tags, t)
		}
	}

	return tags
}

// Parse "label|url" into two trimmed strings.
parse_pipe_pair :: proc(value: string) -> (left: string, right: string, ok: bool) {
	pipe := strings.index_byte(value, '|')
	if pipe < 0 { return "", "", false }
	left = strings.trim_space(value[:pipe])
	right = strings.trim_space(value[pipe + 1:])
	ok = len(left) > 0 && len(right) > 0
	return
}

// Parse site.yaml into Site_Config. Same simple key: value format as frontmatter.
load_site_config :: proc(path: string, allocator := context.allocator) -> (Site_Config, bool) {
	source, ok := read_file(path, allocator)
	if !ok {
		return {}, false
	}

	config := Site_Config{
		footer_links = make([dynamic]Footer_Link, allocator),
		nav_items    = make([dynamic]Nav_Item, allocator),
	}
	lines := strings.split_lines(source, allocator)
	for line in lines {
		key, value, ok := split_yaml_line(line)
		if !ok {
			continue
		}

		switch key {
		case "title":
			config.site_title = value
		case "url":
			config.site_url = value
		case "description":
			config.description = value
		case "footer_tagline":
			config.footer_tagline = value
		case "avatar":
			config.avatar = value
		case "accent_color":
			config.accent_color = value
		case "accent_color_light":
			config.accent_color_light = value
		case "content_dir":
			config.content_dir = value
		case "footer_link":
			if text, url, ok := parse_pipe_pair(value); ok {
				append(&config.footer_links, Footer_Link{text = text, url = url})
			}
		case "nav_item":
			if label, href, ok := parse_pipe_pair(value); ok {
				append(&config.nav_items, Nav_Item{label = label, href = href})
			}
		}
	}

	return config, true
}

parse_int_simple :: proc(s: string) -> int {
	val, _ := strconv.parse_int(s)
	return val
}

// Parse "YYYY-MM-DD" date string into time.Time for RSS day-of-week calculation.
parse_date :: proc(date_str: string, allocator := context.allocator) -> (t: time.Time, ok: bool) {
	parts := strings.split(date_str, "-", allocator)
	if len(parts) != 3 {
		return {}, false
	}

	year := parse_int_simple(parts[0])
	month := parse_int_simple(parts[1])
	day := parse_int_simple(parts[2])

	if year == 0 || month == 0 || day == 0 {
		return {}, false
	}

	return time.components_to_time(i64(year), i64(month), i64(day), 0, 0, 0)
}

// Format time.Time as RFC 822 for RSS: "Mon, 01 Dec 2025 12:34:56 +0000"
format_rss_time :: proc(t: time.Time, allocator := context.allocator) -> string {
	wd := time.weekday(t)
	year, month, day := time.date(t)
	hour, min, sec := time.clock_from_time(t)

	day_names := [7]string{"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}
	month_names := [12]string{"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

	return fmt.aprintf("%s, %02d %s %04d %02d:%02d:%02d +0000",
		day_names[wd], day, month_names[int(month) - 1], year, hour, min, sec,
		allocator = allocator)
}

// Format "YYYY-MM-DD" as RFC 822 for RSS.
format_rss_date :: proc(date_str: string, allocator := context.allocator) -> string {
	t, ok := parse_date(date_str, allocator)
	if !ok {
		return date_str
	}
	return format_rss_time(t, allocator)
}
