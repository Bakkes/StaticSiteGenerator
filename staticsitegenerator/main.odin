package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

// ---------------------------------------------------------------------------
// Scoped Timer
// ---------------------------------------------------------------------------

Scoped_Timer :: struct {
	label: string,
	start: time.Time,
}

scoped_timer_end :: proc(t: Scoped_Timer) {
	d := time.since(t.start)
	ms := time.duration_milliseconds(d)
	fmt.printfln("[%s] %.3fms", t.label, ms)
}

@(deferred_out = scoped_timer_end)
scoped_timer :: proc(label: string) -> Scoped_Timer {
	return Scoped_Timer{label = label, start = time.now()}
}

// ---------------------------------------------------------------------------
// File I/O Helpers
// ---------------------------------------------------------------------------

read_file :: proc(path: string, allocator := context.allocator) -> (string, bool) {
	data, err := os.read_entire_file_from_path(path, allocator)
	if err != nil {
		fmt.eprintfln("Error reading %s: %v", path, err)
		return "", false
	}
	return string(data), true
}

write_file :: proc(path: string, content: string) -> bool {
	err := os.write_entire_file_from_string(path, content)
	if err != nil {
		fmt.eprintfln("Error writing %s: %v", path, err)
		return false
	}
	return true
}

write_output :: proc(output_dir: string, path: string, content: string, count: ^int, allocator := context.allocator) {
	full_path := strings.concatenate({output_dir, "/", path}, allocator)
	if write_file(full_path, content) {
		count^ += 1
	}
}

ensure_dir :: proc(path: string) {
	os.make_directory_all(path)
}

filter_by_tag :: proc(items: []Content_Item, tag: string, allocator := context.allocator) -> [dynamic]Content_Item {
	result := make([dynamic]Content_Item, allocator)
	for item in items {
		for t in item.frontmatter.tags {
			if t == tag {
				append(&result, item)
				break
			}
		}
	}
	return result
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

main :: proc() {
	build_start := time.now()

	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena, block_size = 256 * mem.Kilobyte)
	defer mem.dynamic_arena_destroy(&arena)
	allocator := mem.dynamic_arena_allocator(&arena)
	context.allocator = allocator

	blog_dir := "."
	if len(os.args) > 1 {
		blog_dir = os.args[1]
	}
	// Strip trailing slash
	if len(blog_dir) > 1 && blog_dir[len(blog_dir) - 1] == '/' {
		blog_dir = blog_dir[:len(blog_dir) - 1]
	}

	config_path := strings.concatenate({blog_dir, "/site.yaml"})
	config, config_ok := load_site_config(config_path)
	if !config_ok {
		fmt.eprintfln("Error: failed to read %s", config_path)
		return
	}
	config.blog_dir = blog_dir
	config.output_dir = "dist"

	// If content_dir is set in site.yaml, resolve it relative to blog_dir
	if len(config.content_dir) > 0 {
		config.content_dir = strings.concatenate({blog_dir, "/", config.content_dir})
	} else {
		config.content_dir = blog_dir
	}

	// Load CSS from content_dir
	css_content, css_ok := read_file(strings.concatenate({config.content_dir, "/style.css"}))
	if css_ok {
		config.css = css_content
	}

	// Clean and create output directories
	if err := os.remove_all(config.output_dir); err != nil {
		fmt.eprintfln("Warning: failed to clean %s: %v", config.output_dir, err)
	}
	ensure_dir(config.output_dir)
	ensure_dir(strings.concatenate({config.output_dir, "/articles"}))
	ensure_dir(strings.concatenate({config.output_dir, "/projects"}))

	// Load and parse articles
	articles := load_content(config, "articles")
	slice.sort_by(articles[:], proc(a, b: Content_Item) -> bool {
		return a.frontmatter.date > b.frontmatter.date
	})

	// Load and parse projects
	projects := load_content(config, "projects")
	slice.sort_by(projects[:], proc(a, b: Content_Item) -> bool {
		return a.frontmatter.priority > b.frontmatter.priority
	})

	// Load and parse pages
	home_source, home_ok := read_file(strings.concatenate({config.content_dir, "/home.md"}))
	if !home_ok {
		fmt.eprintln("Error: failed to read home.md")
		return
	}
	home_doc := parse_markdown(home_source)
	home_html := render_html(home_doc, extract_headings(home_doc)[:])

	about_source, about_ok := read_file(strings.concatenate({config.content_dir, "/about.md"}))
	if !about_ok {
		fmt.eprintln("Error: failed to read about.md")
		return
	}
	about_doc := parse_markdown(about_source)
	about_html := render_html(about_doc, extract_headings(about_doc)[:])

	// Generate and write output
	files_written := 0

	write_output(config.output_dir, "index.html", render_home_page(config, home_html, articles[:], projects[:]), &files_written)
	write_output(config.output_dir, "articles.html", render_listing_page(config, "Articles", "articles.html", articles[:], "articles"), &files_written)
	write_output(config.output_dir, "projects.html", render_listing_page(config, "Projects", "projects.html", projects[:], "projects"), &files_written)
	write_output(config.output_dir, "about.html", render_about_page(config, about_html), &files_written)

	for article, idx in articles {
		newer: ^Content_Item = &articles[idx - 1] if idx > 0 else nil
		older: ^Content_Item = &articles[idx + 1] if idx + 1 < len(articles) else nil
		path := strings.concatenate({"articles/", article.slug, ".html"})
		write_output(config.output_dir, path, render_content_page(config, article, "articles", newer, older, articles[:]), &files_written)
	}

	for project in projects {
		path := strings.concatenate({"projects/", project.slug, ".html"})
		write_output(config.output_dir, path, render_content_page(config, project, "projects"), &files_written)
	}

	// Generate tag pages
	tags := collect_tags(articles[:], projects[:])
	if len(tags) > 0 {
		ensure_dir(strings.concatenate({config.output_dir, "/tags"}))

		// Build tag counts for the index page
		tag_counts := make([dynamic]Tag_Count)
		for tag in tags {
			tag_articles := filter_by_tag(articles[:], tag)
			tag_projects := filter_by_tag(projects[:], tag)
			append(&tag_counts, Tag_Count{name = tag, count = len(tag_articles) + len(tag_projects)})
			tag_path := strings.concatenate({"tags/", slugify(tag), ".html"})
			write_output(config.output_dir, tag_path, render_tag_page(config, tag, tag_articles[:], tag_projects[:]), &files_written)
		}

		// Sort by count descending
		slice.sort_by(tag_counts[:], proc(a, b: Tag_Count) -> bool {
			return a.count > b.count
		})

		write_output(config.output_dir, "tags/index.html", render_tags_index_page(config, tag_counts[:]), &files_written)
	}

	write_output(config.output_dir, "feed.xml", render_rss_feed(config, articles[:], projects[:]), &files_written)
	write_output(config.output_dir, "sitemap.xml", render_sitemap(config, articles[:], projects[:], tags[:]), &files_written)
	write_output(config.output_dir, "404.html", render_404_page(config), &files_written)

	// Copy static assets
	static_copied := copy_static_assets(config.content_dir, config.output_dir)
	files_written += static_copied

	build_ms := time.duration_milliseconds(time.since(build_start))
	total_bytes := (len(arena.used_blocks) + 1) * arena.block_size
	fmt.printfln("Built %d files (%d articles, %d projects) in %.1fms | ~%dKB memory", files_written, len(articles), len(projects), build_ms, total_bytes / 1024)

	// Validate output — exit non-zero on failure so CI stops before deploy
	if !validate_output(config) {
		os.exit(1)
	}
}

// ---------------------------------------------------------------------------
// Content Loading
// ---------------------------------------------------------------------------

load_content :: proc(config: Site_Config, subdir: string, allocator := context.allocator) -> [dynamic]Content_Item {
	items := make([dynamic]Content_Item, allocator)
	dir := strings.concatenate({config.content_dir, "/", subdir}, allocator)

	entries, err := os.read_all_directory_by_path(dir, allocator)
	if err != nil {
		fmt.eprintfln("Error reading %s directory: %v", subdir, err)
		return items
	}

	for entry in entries {
		if !strings.has_suffix(entry.name, ".md") {
			continue
		}

		source, ok := read_file(entry.fullpath, allocator)
		if !ok {
			continue
		}

		fm_text, body := split_frontmatter(source)
		frontmatter := parse_frontmatter(fm_text, allocator)
		slug := strings.trim_suffix(entry.name, ".md")

		doc := parse_markdown(body, allocator)
		headings := extract_headings(doc, allocator)
		body_html := render_html(doc, headings[:], allocator)

		if frontmatter.draft {
			continue
		}

		append(&items, Content_Item{
			frontmatter = frontmatter,
			slug        = slug,
			source_path = entry.fullpath,
			body_html   = body_html,
			headings    = headings,
		})
	}

	return items
}

// ---------------------------------------------------------------------------
// Tag Collection
// ---------------------------------------------------------------------------

collect_tags :: proc(articles: []Content_Item, projects: []Content_Item, allocator := context.allocator) -> [dynamic]string {
	seen := make(map[string]bool, allocator = context.temp_allocator)
	tags := make([dynamic]string, allocator)
	for items in ([2][]Content_Item{articles, projects}) {
		for item in items {
			for tag in item.frontmatter.tags {
				if !seen[tag] {
					seen[tag] = true
					append(&tags, tag)
				}
			}
		}
	}
	return tags
}

Tag_Count :: struct {
	name:  string,
	count: int,
}

// ---------------------------------------------------------------------------
// Static Asset Copying
// ---------------------------------------------------------------------------

copy_static_assets :: proc(blog_dir: string, output_dir: string, allocator := context.allocator) -> int {
	copied := 0
	copy_dir_recursive(blog_dir, output_dir, &copied, allocator)
	return copied
}

copy_dir_recursive :: proc(src_dir: string, dst_dir: string, copied: ^int, allocator := context.allocator) {
	entries, err := os.read_all_directory_by_path(src_dir, allocator)
	if err != nil {
		return
	}

	for entry in entries {
		if strings.has_prefix(entry.name, ".") || strings.has_suffix(entry.name, ".md") || entry.name == "site.yaml" || entry.name == "style.css" {
			continue
		}

		dst_path := strings.concatenate({dst_dir, "/", entry.name}, allocator)

		if entry.type == .Directory {
			ensure_dir(dst_path)
			copy_dir_recursive(entry.fullpath, dst_path, copied, allocator)
		} else {
			data, read_err := os.read_entire_file_from_path(entry.fullpath, allocator)
			if read_err != nil {
				continue
			}
			write_err := os.write_entire_file(dst_path, data)
			if write_err == nil {
				copied^ += 1
			}
		}
	}
}
