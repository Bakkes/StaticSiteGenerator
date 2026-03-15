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

ensure_dir :: proc(path: string) {
	os.make_directory_all(path)
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

	blog_dir := "blog"
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

	// Clean and create output directories
	os.remove_all(config.output_dir)
	ensure_dir(config.output_dir)
	ensure_dir(strings.concatenate({config.output_dir, "/articles"}))
	ensure_dir(strings.concatenate({config.output_dir, "/projects"}))

	// Load and parse articles
	articles := load_articles(config)
	slice.sort_by(articles[:], proc(a, b: Article) -> bool {
		return a.frontmatter.date > b.frontmatter.date
	})

	// Load and parse projects
	projects := load_projects(config)
	slice.sort_by(projects[:], proc(a, b: Project) -> bool {
		return a.frontmatter.priority > b.frontmatter.priority
	})

	// Load and parse pages
	home_source, home_ok := read_file(strings.concatenate({config.blog_dir, "/home.md"}))
	if !home_ok {
		fmt.eprintln("Error: failed to read home.md")
		return
	}
	home_html := render_html(parse_markdown(home_source))

	about_source, about_ok := read_file(strings.concatenate({config.blog_dir, "/about.md"}))
	if !about_ok {
		fmt.eprintln("Error: failed to read about.md")
		return
	}
	about_html := render_html(parse_markdown(about_source))

	// Generate and write output
	files_written := 0

	if write_file(
		strings.concatenate({config.output_dir, "/index.html"}),
		render_home_page(config, home_html, articles[:], projects[:]),
	) {
		files_written += 1
	}

	if write_file(
		strings.concatenate({config.output_dir, "/articles.html"}),
		render_articles_page(config, articles[:]),
	) {
		files_written += 1
	}

	if write_file(
		strings.concatenate({config.output_dir, "/about.html"}),
		render_about_page(config, about_html),
	) {
		files_written += 1
	}

	if write_file(
		strings.concatenate({config.output_dir, "/projects.html"}),
		render_projects_page(config, projects[:]),
	) {
		files_written += 1
	}

	for &article, idx in articles {
		prev: ^Article = &articles[idx - 1] if idx > 0 else nil
		next: ^Article = &articles[idx + 1] if idx + 1 < len(articles) else nil
		path := strings.concatenate({config.output_dir, "/articles/", article.slug, ".html"})
		if write_file(path, render_article_page(config, article, prev, next, articles[:])) {
			files_written += 1
		}
	}

	for project in projects {
		path := strings.concatenate({config.output_dir, "/projects/", project.slug, ".html"})
		if write_file(path, render_project_page(config, project)) {
			files_written += 1
		}
	}

	// Generate tag pages
	tags := collect_tags(articles[:], projects[:])
	if len(tags) > 0 {
		ensure_dir(strings.concatenate({config.output_dir, "/tags"}))
		for tag in tags {
			tag_articles := make([dynamic]Article)
			tag_projects := make([dynamic]Project)
			for article in articles {
				for t in article.frontmatter.tags {
					if t == tag {
						append(&tag_articles, article)
						break
					}
				}
			}
			for project in projects {
				for t in project.frontmatter.tags {
					if t == tag {
						append(&tag_projects, project)
						break
					}
				}
			}
			path := strings.concatenate({config.output_dir, "/tags/", slugify(tag), ".html"})
			if write_file(path, render_tag_page(config, tag, tag_articles[:], tag_projects[:])) {
				files_written += 1
			}
		}
	}

	if write_file(
		strings.concatenate({config.output_dir, "/feed.xml"}),
		render_rss_feed(config, articles[:], projects[:]),
	) {
		files_written += 1
	}

	if write_file(
		strings.concatenate({config.output_dir, "/sitemap.xml"}),
		render_sitemap(config, articles[:], projects[:], tags[:]),
	) {
		files_written += 1
	}

	if write_file(
		strings.concatenate({config.output_dir, "/404.html"}),
		render_404_page(config),
	) {
		files_written += 1
	}

	// Copy static assets
	static_copied := copy_static_assets(config.blog_dir, config.output_dir)
	files_written += static_copied

	build_ms := time.duration_milliseconds(time.since(build_start))
	total_bytes := (len(arena.used_blocks) + 1) * arena.block_size + len(arena.out_band_allocations) * arena.out_band_size
	fmt.printfln("Built %d files (%d articles, %d projects) in %.1fms | ~%dKB memory", files_written, len(articles), len(projects), build_ms, total_bytes / 1024)

	// Validate output — exit non-zero on failure so CI stops before deploy
	if !validate_output(config) {
		os.exit(1)
	}
}

// ---------------------------------------------------------------------------
// Article Loading
// ---------------------------------------------------------------------------

load_articles :: proc(config: Site_Config, allocator := context.allocator) -> [dynamic]Article {
	articles := make([dynamic]Article, allocator)
	articles_dir := strings.concatenate({config.blog_dir, "/articles"}, allocator)

	entries, err := os.read_all_directory_by_path(articles_dir, allocator)
	if err != nil {
		fmt.eprintfln("Error reading articles directory: %v", err)
		return articles
	}

	for entry in entries {
		if !strings.has_suffix(entry.name, ".md") {
			continue
		}

		source, ok := read_file(entry.fullpath, allocator)
		if !ok {
			continue
		}

		fm_text, body := split_frontmatter(source, allocator)
		frontmatter := parse_frontmatter(fm_text, allocator)
		slug := strings.trim_suffix(entry.name, ".md")

		doc := parse_markdown(body, allocator)
		body_html := render_html(doc, allocator)
		headings := extract_headings(doc, allocator)

		if frontmatter.draft {
			continue
		}

		append(&articles, Article{
			frontmatter = frontmatter,
			slug        = slug,
			source_path = entry.fullpath,
			body_html   = body_html,
			headings    = headings,
		})
	}

	return articles
}

// ---------------------------------------------------------------------------
// Project Loading
// ---------------------------------------------------------------------------

load_projects :: proc(config: Site_Config, allocator := context.allocator) -> [dynamic]Project {
	projects := make([dynamic]Project, allocator)
	projects_dir := strings.concatenate({config.blog_dir, "/projects"}, allocator)

	entries, err := os.read_all_directory_by_path(projects_dir, allocator)
	if err != nil {
		fmt.eprintfln("Error reading projects directory: %v", err)
		return projects
	}

	for entry in entries {
		if !strings.has_suffix(entry.name, ".md") {
			continue
		}

		source, ok := read_file(entry.fullpath, allocator)
		if !ok {
			continue
		}

		fm_text, body := split_frontmatter(source, allocator)
		frontmatter := parse_frontmatter(fm_text, allocator)
		slug := strings.trim_suffix(entry.name, ".md")

		doc := parse_markdown(body, allocator)
		body_html := render_html(doc, allocator)
		headings := extract_headings(doc, allocator)

		if frontmatter.draft {
			continue
		}

		append(&projects, Project{
			frontmatter = frontmatter,
			slug        = slug,
			source_path = entry.fullpath,
			body_html   = body_html,
			headings    = headings,
		})
	}

	return projects
}

// ---------------------------------------------------------------------------
// Tag Collection
// ---------------------------------------------------------------------------

collect_tags :: proc(articles: []Article, projects: []Project, allocator := context.allocator) -> [dynamic]string {
	tags := make([dynamic]string, allocator)
	for article in articles {
		for tag in article.frontmatter.tags {
			if !tag_exists(tags[:], tag) {
				append(&tags, tag)
			}
		}
	}
	for project in projects {
		for tag in project.frontmatter.tags {
			if !tag_exists(tags[:], tag) {
				append(&tags, tag)
			}
		}
	}
	return tags
}

tag_exists :: proc(tags: []string, tag: string) -> bool {
	for t in tags {
		if t == tag {
			return true
		}
	}
	return false
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
			write_err := os.write_entire_file_from_string(dst_path, string(data))
			if write_err == nil {
				copied^ += 1
			}
		}
	}
}
