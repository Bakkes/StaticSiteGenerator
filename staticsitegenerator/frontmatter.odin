package main

import "core:strings"
import "core:strconv"
import "core:time"

// Split a markdown file into frontmatter text and body text.
// Frontmatter is delimited by --- lines at the top of the file.
split_frontmatter :: proc(source: string, allocator := context.allocator) -> (fm_text: string, body: string) {
	lines := strings.split_lines(source, allocator)
	if len(lines) == 0 || strings.trim_space(lines[0]) != "---" {
		return "", source
	}

	// Find closing ---
	for i in 1 ..< len(lines) {
		if strings.trim_space(lines[i]) == "---" {
			fm := strings.join(lines[1:i], "\n", allocator)
			body_lines := lines[i + 1:]
			b := strings.join(body_lines, "\n", allocator)
			return fm, b
		}
	}

	return "", source
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
		colon := strings.index_byte(line, ':')
		if colon < 0 {
			continue
		}
		key := strings.trim_space(line[:colon])
		value := strings.trim_space(line[colon + 1:])

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
		colon := strings.index_byte(line, ':')
		if colon < 0 {
			continue
		}
		key := strings.trim_space(line[:colon])
		value := strings.trim_space(line[colon + 1:])

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
			pipe := strings.index_byte(value, '|')
			if pipe >= 0 {
				text := strings.trim_space(value[:pipe])
				url := strings.trim_space(value[pipe + 1:])
				if len(text) > 0 && len(url) > 0 {
					append(&config.footer_links, Footer_Link{text = text, url = url})
				}
			}
		case "nav_item":
			pipe := strings.index_byte(value, '|')
			if pipe >= 0 {
				label := strings.trim_space(value[:pipe])
				href := strings.trim_space(value[pipe + 1:])
				if len(label) > 0 && len(href) > 0 {
					append(&config.nav_items, Nav_Item{label = label, href = href})
				}
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

	b := strings.builder_make(allocator)
	buf: [20]byte
	strings.write_string(&b, day_names[wd])
	strings.write_string(&b, ", ")
	if day < 10 { strings.write_byte(&b, '0') }
	strings.write_string(&b, strconv.write_int(buf[:], i64(day), 10))
	strings.write_byte(&b, ' ')
	strings.write_string(&b, month_names[int(month) - 1])
	strings.write_byte(&b, ' ')
	strings.write_string(&b, strconv.write_int(buf[:], i64(year), 10))
	strings.write_byte(&b, ' ')
	if hour < 10 { strings.write_byte(&b, '0') }
	strings.write_string(&b, strconv.write_int(buf[:], i64(hour), 10))
	strings.write_byte(&b, ':')
	if min < 10 { strings.write_byte(&b, '0') }
	strings.write_string(&b, strconv.write_int(buf[:], i64(min), 10))
	strings.write_byte(&b, ':')
	if sec < 10 { strings.write_byte(&b, '0') }
	strings.write_string(&b, strconv.write_int(buf[:], i64(sec), 10))
	strings.write_string(&b, " +0000")
	return strings.to_string(b)
}

// Format "YYYY-MM-DD" as RFC 822 for RSS.
format_rss_date :: proc(date_str: string, allocator := context.allocator) -> string {
	t, ok := parse_date(date_str, allocator)
	if !ok {
		return date_str
	}
	return format_rss_time(t, allocator)
}
