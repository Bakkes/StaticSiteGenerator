package main

import "core:fmt"
import "core:slice"
import "core:strings"

HOME_MAX_ARTICLES :: 8
HOME_MAX_PROJECTS :: 5

// ---------------------------------------------------------------------------
// HTML Page Shell
// ---------------------------------------------------------------------------

// Writes the HTML page header up to and including <main>.
// `prefix` is "" for root pages, "../" for articles/.
render_page_header :: proc(
	b: ^strings.Builder,
	config: Site_Config,
	title: string,
	active_nav: string,
	prefix: string,
	page_description: string = "",
	page_path: string = "",
) {
	strings.write_string(b, `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>`)
	write_html_escaped(b, title)
	strings.write_string(b, " | ")
	write_html_escaped(b, config.site_title)
	strings.write_string(b, "</title>\n")
	// Use page-specific description, fall back to site description
	desc := page_description if len(page_description) > 0 else config.description
	if len(desc) > 0 {
		strings.write_string(b, `<meta name="description" content="`)
		write_html_escaped(b, desc)
		strings.write_string(b, "\">\n")
		strings.write_string(b, `<meta property="og:description" content="`)
		write_html_escaped(b, desc)
		strings.write_string(b, "\">\n")
	}
	strings.write_string(b, `<meta property="og:title" content="`)
	write_html_escaped(b, title)
	strings.write_string(b, "\">\n")
	strings.write_string(b, `<meta property="og:type" content="website">`)
	strings.write_string(b, "\n")
	if len(page_path) > 0 {
		strings.write_string(b, `<link rel="canonical" href="`)
		write_html_escaped(b, config.site_url)
		strings.write_string(b, "/")
		strings.write_string(b, page_path)
		strings.write_string(b, "\">\n")
	}
	if len(config.css) > 0 {
		strings.write_string(b, "<style>")
		strings.write_string(b, config.css)
		strings.write_string(b, "</style>\n")
	}
	if len(config.accent_color) > 0 {
		strings.write_string(b, "<style>:root{--accent:")
		write_html_escaped(b, config.accent_color)
		strings.write_string(b, "}")
		light := config.accent_color_light if len(config.accent_color_light) > 0 else config.accent_color
		strings.write_string(b, "body:has(#theme-toggle:checked){--accent:")
		write_html_escaped(b, light)
		strings.write_string(b, "}</style>\n")
	}
	strings.write_string(b, `<link rel="alternate" type="application/rss+xml" title="`)
	write_html_escaped(b, config.site_title)
	strings.write_string(b, `" href="`)
	strings.write_string(b, prefix)
	strings.write_string(b, `feed.xml">
</head>
<body>
<input type="checkbox" id="theme-toggle">
<script>var c=document.getElementById("theme-toggle");if(localStorage.getItem("theme")==="light")c.checked=true;c.onchange=function(){localStorage.setItem("theme",c.checked?"light":"dark")}</script>
<header>
<a class="site-title" href="`)
	strings.write_string(b, prefix)
	strings.write_string(b, `index.html">`)
	write_html_escaped(b, config.site_title)
	strings.write_string(b, `</a>`)
	if len(config.avatar) > 0 {
		strings.write_string(b, `<img class="avatar" src="`)
		strings.write_string(b, prefix)
		write_html_escaped(b, config.avatar)
		strings.write_string(b, `" alt="" width="32" height="32">`)
	}
	strings.write_string(b, "\n")
	render_nav(b, config.nav_items[:], active_nav, prefix)
	strings.write_string(b, "</header>\n<hr>\n")
	strings.write_string(b, "<main>\n")
}

// Writes </main>, footer, and closing HTML tags.
render_page_footer :: proc(b: ^strings.Builder, config: Site_Config, prefix: string) {
	strings.write_string(b, "\n</main>\n<hr>\n")
	strings.write_string(b, "<footer>\n")
	if len(config.footer_tagline) > 0 {
		tagline_inlines := parse_inlines(config.footer_tagline)
		rs := Render_State{b = b}
		render_inlines(&rs, tagline_inlines[:])
		strings.write_string(b, "<br>")
	}
	first_link := true
	for link in config.footer_links {
		if !first_link {
			strings.write_string(b, " · ")
		}
		strings.write_string(b, `<a href="`)
		write_html_escaped(b, link.url)
		strings.write_string(b, `">`)
		write_html_escaped(b, link.text)
		strings.write_string(b, "</a>")
		first_link = false
	}
	if !first_link {
		strings.write_string(b, " · ")
	}
	strings.write_string(b, `<a href="`)
	strings.write_string(b, prefix)
	strings.write_string(b, `feed.xml">RSS</a>`)
	strings.write_string(b, "\n</footer>\n</body>\n</html>\n")
}

render_nav :: proc(b: ^strings.Builder, nav_items: []Nav_Item, active_nav: string, prefix: string) {
	strings.write_string(b, "<nav>\n")

	for item in nav_items {
		strings.write_string(b, `<a href="`)
		strings.write_string(b, prefix)
		strings.write_string(b, item.href)
		strings.write_string(b, `"`)
		if item.href == active_nav {
			strings.write_string(b, ` class="active"`)
		}
		strings.write_string(b, ">")
		strings.write_string(b, item.label)
		strings.write_string(b, "</a>\n")
	}

	strings.write_string(b, `<label for="theme-toggle" class="theme-label"></label>`)
	strings.write_string(b, "\n</nav>\n")
}

// ---------------------------------------------------------------------------
// Date helper — writes date with optional "modified" tooltip asterisk
// ---------------------------------------------------------------------------

write_date :: proc(b: ^strings.Builder, fm: Frontmatter) {
	if len(fm.modified) > 0 {
		strings.write_string(b, `<abbr class="modified" title="Last updated `)
		write_html_escaped(b, fm.modified)
		strings.write_string(b, `">`)
		write_html_escaped(b, fm.date)
		strings.write_string(b, `*</abbr>`)
	} else {
		write_html_escaped(b, fm.date)
	}
}

write_toc :: proc(b: ^strings.Builder, headings: []Heading_Info) {
	if len(headings) == 0 {
		return
	}
	strings.write_string(b, "<details class=\"toc\">\n<summary>Table of Contents</summary>\n")

	// Track nesting depth to open/close <ul> for sub-levels
	min_level := headings[0].level
	for h in headings[1:] {
		if h.level < min_level {
			min_level = h.level
		}
	}

	current_level := min_level
	strings.write_string(b, "<ul>\n")

	for h in headings {
		// Open nested lists for deeper headings
		for current_level < h.level {
			strings.write_string(b, "<ul>\n")
			current_level += 1
		}
		// Close nested lists for shallower headings
		for current_level > h.level {
			strings.write_string(b, "</ul>\n")
			current_level -= 1
		}
		strings.write_string(b, `<li><a href="#`)
		strings.write_string(b, h.id)
		strings.write_string(b, `">`)
		write_html_escaped(b, h.text)
		strings.write_string(b, "</a></li>\n")
	}

	// Close any remaining open lists
	for current_level > min_level {
		strings.write_string(b, "</ul>\n")
		current_level -= 1
	}
	strings.write_string(b, "</ul>\n</details>\n")
}

write_series_nav :: proc(b: ^strings.Builder, current: Content_Item, all_items: []Content_Item) {
	// Collect items in the same series, sorted by series_part
	series_items := make([dynamic]Content_Item, context.temp_allocator)
	for item in all_items {
		if item.frontmatter.series == current.frontmatter.series {
			append(&series_items, item)
		}
	}
	if len(series_items) < 2 {
		return
	}

	// Sort by series_part
	slice.sort_by(series_items[:], proc(a, b: Content_Item) -> bool {
		return a.frontmatter.series_part < b.frontmatter.series_part
	})

	strings.write_string(b, "<nav class=\"series\">\n<strong>")
	write_html_escaped(b, current.frontmatter.series)
	strings.write_string(b, "</strong>\n<ol>\n")
	for item in series_items {
		if item.slug == current.slug {
			strings.write_string(b, "<li class=\"current\">")
			write_html_escaped(b, item.frontmatter.title)
			strings.write_string(b, "</li>\n")
		} else {
			strings.write_string(b, "<li><a href=\"")
			strings.write_string(b, item.slug)
			strings.write_string(b, ".html\">")
			write_html_escaped(b, item.frontmatter.title)
			strings.write_string(b, "</a></li>\n")
		}
	}
	strings.write_string(b, "</ol>\n</nav>\n")
}

write_tags :: proc(b: ^strings.Builder, tags: []string, prefix: string) {
	if len(tags) == 0 {
		return
	}
	strings.write_string(b, " &middot; <span class=\"tags\">")
	for tag, idx in tags {
		if idx > 0 {
			strings.write_string(b, " ")
		}
		strings.write_string(b, `<a class="tag" href="`)
		strings.write_string(b, prefix)
		strings.write_string(b, "tags/")
		strings.write_string(b, slugify(tag))
		strings.write_string(b, `.html">`)
		write_html_escaped(b, tag)
		strings.write_string(b, "</a>")
	}
	strings.write_string(b, "</span>")
}

write_description :: proc(b: ^strings.Builder, fm: Frontmatter) {
	if len(fm.description) > 0 {
		strings.write_string(b, `<span class="description">`)
		write_html_escaped(b, fm.description)
		strings.write_string(b, "</span>")
	}
}

write_content_list_item :: proc(b: ^strings.Builder, item: Content_Item, href_prefix: string, show_description := true) {
	strings.write_string(b, "<li><span class=\"date\">")
	write_html_escaped(b, item.frontmatter.date)
	strings.write_string(b, "</span> <a href=\"")
	strings.write_string(b, href_prefix)
	strings.write_string(b, item.slug)
	strings.write_string(b, ".html\">")
	write_html_escaped(b, item.frontmatter.title)
	strings.write_string(b, "</a>")
	if show_description {
		write_description(b, item.frontmatter)
	}
	strings.write_string(b, "</li>\n")
}

// ---------------------------------------------------------------------------
// Home Page
// ---------------------------------------------------------------------------

render_home_page :: proc(config: Site_Config, home_html: string, articles: []Article, projects: []Project, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	render_page_header(&b, config, "Home", "index.html", "", page_path = "index.html")

	// Home content
	strings.write_string(&b, home_html)

	// Recent articles
	strings.write_string(&b, "\n<h2>Articles</h2>\n<ul class=\"article-list\">\n")
	for article in articles[:min(len(articles), HOME_MAX_ARTICLES)] {
		write_content_list_item(&b, article, "articles/")
	}
	strings.write_string(&b, "</ul>\n")
	strings.write_string(&b, "<p><a href=\"articles.html\">All articles &rarr;</a></p>\n")

	// Recent projects
	if len(projects) > 0 {
		strings.write_string(&b, "\n<h2>Projects</h2>\n<ul class=\"article-list\">\n")
		for project in projects[:min(len(projects), HOME_MAX_PROJECTS)] {
			write_content_list_item(&b, project, "projects/")
		}
		strings.write_string(&b, "</ul>\n")
		strings.write_string(&b, "<p><a href=\"projects.html\">All projects &rarr;</a></p>\n")
	}

	render_page_footer(&b, config, "")
	return strings.to_string(b)
}

// ---------------------------------------------------------------------------
// Content Listing Page (Articles / Projects)
// ---------------------------------------------------------------------------

render_listing_page :: proc(config: Site_Config, title: string, nav_active: string, items: []Content_Item, section: string, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	render_page_header(&b, config, title, nav_active, "", page_path = nav_active)

	strings.write_string(&b, "<h1>")
	write_html_escaped(&b, title)
	strings.write_string(&b, "</h1>\n<ul class=\"article-list\">\n")
	href_prefix := strings.concatenate({section, "/"}, allocator)
	for item in items {
		write_content_list_item(&b, item, href_prefix)
	}
	strings.write_string(&b, "</ul>\n")

	render_page_footer(&b, config, "")
	return strings.to_string(b)
}

// ---------------------------------------------------------------------------
// Individual Content Page (Article / Project)
// ---------------------------------------------------------------------------

render_content_page :: proc(
	config: Site_Config,
	item: Content_Item,
	section: string,
	newer: ^Content_Item = nil,
	older: ^Content_Item = nil,
	all_items: []Content_Item = nil,
	allocator := context.allocator,
) -> string {
	b := strings.builder_make(allocator)
	nav_active := strings.concatenate({section, ".html"}, allocator)
	item_path := strings.concatenate({section, "/", item.slug, ".html"}, allocator)
	render_page_header(&b, config, item.frontmatter.title, nav_active, "../", item.frontmatter.description, item_path)

	// Content meta
	strings.write_string(&b, "<div class=\"article-meta\">")
	write_date(&b, item.frontmatter)
	if len(item.frontmatter.author) > 0 {
		strings.write_string(&b, " &middot; ")
		write_html_escaped(&b, item.frontmatter.author)
	}
	write_tags(&b, item.frontmatter.tags[:], "../")
	strings.write_string(&b, "</div>\n")

	if item.frontmatter.toc {
		write_toc(&b, item.headings[:])
	}

	strings.write_string(&b, item.body_html)

	// Series navigation
	if len(item.frontmatter.series) > 0 && all_items != nil {
		write_series_nav(&b, item, all_items)
	}

	// Older / Newer navigation
	if newer != nil || older != nil {
		strings.write_string(&b, "<nav class=\"article-nav\">\n")
		if older != nil {
			strings.write_string(&b, "<a class=\"article-nav-prev\" href=\"")
			strings.write_string(&b, older.slug)
			strings.write_string(&b, ".html\">&larr; ")
			write_html_escaped(&b, older.frontmatter.title)
			strings.write_string(&b, "</a>\n")
		}
		if newer != nil {
			strings.write_string(&b, "<a class=\"article-nav-next\" href=\"")
			strings.write_string(&b, newer.slug)
			strings.write_string(&b, ".html\">")
			write_html_escaped(&b, newer.frontmatter.title)
			strings.write_string(&b, " &rarr;</a>\n")
		}
		strings.write_string(&b, "</nav>\n")
	}

	render_page_footer(&b, config, "../")
	return strings.to_string(b)
}

// ---------------------------------------------------------------------------
// Tag Page
// ---------------------------------------------------------------------------

render_tag_page :: proc(config: Site_Config, tag: string, articles: []Content_Item, projects: []Content_Item, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	render_page_header(&b, config, tag, "articles.html", "../")

	strings.write_string(&b, "<h1>Tagged: ")
	write_html_escaped(&b, tag)
	strings.write_string(&b, "</h1>\n")

	if len(articles) > 0 {
		strings.write_string(&b, "<h2>Articles</h2>\n<ul class=\"article-list\">\n")
		for article in articles {
			write_content_list_item(&b, article, "../articles/", show_description = false)
		}
		strings.write_string(&b, "</ul>\n")
	}

	if len(projects) > 0 {
		strings.write_string(&b, "<h2>Projects</h2>\n<ul class=\"article-list\">\n")
		for project in projects {
			write_content_list_item(&b, project, "../projects/", show_description = false)
		}
		strings.write_string(&b, "</ul>\n")
	}

	render_page_footer(&b, config, "../")
	return strings.to_string(b)
}

render_tags_index_page :: proc(config: Site_Config, tag_counts: []Tag_Count, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	render_page_header(&b, config, "Tags", "articles.html", "../", page_path = "tags/index.html")

	strings.write_string(&b, "<h1>Tags</h1>\n<ul class=\"tag-list\">\n")
	for tc in tag_counts {
		strings.write_string(&b, `<li><a class="tag" href="`)
		strings.write_string(&b, slugify(tc.name, allocator))
		strings.write_string(&b, `.html">`)
		write_html_escaped(&b, tc.name)
		fmt.sbprintf(&b, `</a> <span class="count">(%d)</span></li>`, tc.count)
		strings.write_string(&b, "\n")
	}
	strings.write_string(&b, "</ul>\n")

	render_page_footer(&b, config, "../")
	return strings.to_string(b)
}

// ---------------------------------------------------------------------------
// 404 Page
// ---------------------------------------------------------------------------

render_404_page :: proc(config: Site_Config, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	render_page_header(&b, config, "Not Found", "", "")
	strings.write_string(&b, "<h1>404</h1>\n<p>Page not found. <a href=\"index.html\">Go home</a>.</p>\n")
	render_page_footer(&b, config, "")
	return strings.to_string(b)
}

// ---------------------------------------------------------------------------
// About Page
// ---------------------------------------------------------------------------

render_about_page :: proc(config: Site_Config, about_html: string, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	render_page_header(&b, config, "About", "about.html", "", page_path = "about.html")
	strings.write_string(&b, about_html)
	render_page_footer(&b, config, "")
	return strings.to_string(b)
}
