package main

import "core:fmt"
import "core:strings"

// ---------------------------------------------------------------------------
// HTML Page Shell
// ---------------------------------------------------------------------------

// Renders a complete HTML page. `prefix` is "" for root pages, "../" for articles/.
render_page :: proc(
	b: ^strings.Builder,
	config: Site_Config,
	title: string,
	active_nav: string,
	prefix: string,
	content: string,
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
	strings.write_string(b, content)
	strings.write_string(b, "\n</main>\n<hr>\n")
	strings.write_string(b, "<footer>\n")
	if len(config.footer_tagline) > 0 {
		tagline_inlines := parse_inlines(config.footer_tagline)
		sn_counter := 0
		render_inlines(b, tagline_inlines[:], nil, &sn_counter)
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
		strings.write_string(b, fm.date)
		strings.write_string(b, `*</abbr>`)
	} else {
		strings.write_string(b, fm.date)
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

write_series_nav :: proc(b: ^strings.Builder, current: Article, all_articles: []Article) {
	// Collect articles in the same series, sorted by series_part
	series_articles := make([dynamic]Article, context.temp_allocator)
	for article in all_articles {
		if article.frontmatter.series == current.frontmatter.series {
			append(&series_articles, article)
		}
	}
	if len(series_articles) < 2 {
		return
	}

	// Sort by series_part
	for i in 1 ..< len(series_articles) {
		j := i
		for j > 0 && series_articles[j].frontmatter.series_part < series_articles[j - 1].frontmatter.series_part {
			series_articles[j], series_articles[j - 1] = series_articles[j - 1], series_articles[j]
			j -= 1
		}
	}

	strings.write_string(b, "<nav class=\"series\">\n<strong>")
	write_html_escaped(b, current.frontmatter.series)
	strings.write_string(b, "</strong>\n<ol>\n")
	for article in series_articles {
		if article.slug == current.slug {
			strings.write_string(b, "<li class=\"current\">")
			write_html_escaped(b, article.frontmatter.title)
			strings.write_string(b, "</li>\n")
		} else {
			strings.write_string(b, "<li><a href=\"")
			strings.write_string(b, article.slug)
			strings.write_string(b, ".html\">")
			write_html_escaped(b, article.frontmatter.title)
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

// ---------------------------------------------------------------------------
// Home Page
// ---------------------------------------------------------------------------

render_home_page :: proc(config: Site_Config, home_html: string, articles: []Article, projects: []Project, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	content := strings.builder_make(allocator)

	// Home content
	strings.write_string(&content, home_html)

	// Recent articles (up to 8)
	strings.write_string(&content, "\n<h2>Articles</h2>\n<ul class=\"article-list\">\n")
	for article in articles[:min(len(articles), 8)] {
		strings.write_string(&content, "<li><span class=\"date\">")
		strings.write_string(&content, article.frontmatter.date)
		strings.write_string(&content, "</span> <a href=\"articles/")
		strings.write_string(&content, article.slug)
		strings.write_string(&content, ".html\">")
		write_html_escaped(&content, article.frontmatter.title)
		strings.write_string(&content, "</a>")
		write_description(&content, article.frontmatter)
		strings.write_string(&content, "</li>\n")
	}
	strings.write_string(&content, "</ul>\n")
	strings.write_string(&content, "<p><a href=\"articles.html\">All articles &rarr;</a></p>\n")

	// Recent projects (up to 5)
	if len(projects) > 0 {
		strings.write_string(&content, "\n<h2>Projects</h2>\n<ul class=\"article-list\">\n")
		for project in projects[:min(len(projects), 5)] {
			strings.write_string(&content, "<li><span class=\"date\">")
			strings.write_string(&content, project.frontmatter.date)
			strings.write_string(&content, "</span> <a href=\"projects/")
			strings.write_string(&content, project.slug)
			strings.write_string(&content, ".html\">")
			write_html_escaped(&content, project.frontmatter.title)
			strings.write_string(&content, "</a>")
			write_description(&content, project.frontmatter)
			strings.write_string(&content, "</li>\n")
		}
		strings.write_string(&content, "</ul>\n")
		strings.write_string(&content, "<p><a href=\"projects.html\">All projects &rarr;</a></p>\n")
	}

	render_page(&b, config, "Home", "index.html", "", strings.to_string(content), page_path = "index.html")
	return strings.to_string(b)
}

// ---------------------------------------------------------------------------
// Articles Listing Page
// ---------------------------------------------------------------------------

render_articles_page :: proc(config: Site_Config, articles: []Article, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	content := strings.builder_make(allocator)

	strings.write_string(&content, "<h1>Articles</h1>\n<ul class=\"article-list\">\n")
	for article in articles {
		strings.write_string(&content, "<li><span class=\"date\">")
		strings.write_string(&content, article.frontmatter.date)
		strings.write_string(&content, "</span> <a href=\"articles/")
		strings.write_string(&content, article.slug)
		strings.write_string(&content, ".html\">")
		write_html_escaped(&content, article.frontmatter.title)
		strings.write_string(&content, "</a>")
		write_description(&content, article.frontmatter)
		strings.write_string(&content, "</li>\n")
	}
	strings.write_string(&content, "</ul>\n")

	render_page(&b, config, "Articles", "articles.html", "", strings.to_string(content), page_path = "articles.html")
	return strings.to_string(b)
}

// ---------------------------------------------------------------------------
// Individual Article Page
// ---------------------------------------------------------------------------

render_article_page :: proc(
	config: Site_Config,
	article: Article,
	prev: ^Article,
	next: ^Article,
	all_articles: []Article = nil,
	allocator := context.allocator,
) -> string {
	b := strings.builder_make(allocator)
	content := strings.builder_make(allocator)

	// Article meta
	strings.write_string(&content, "<div class=\"article-meta\">")
	write_date(&content, article.frontmatter)
	if len(article.frontmatter.author) > 0 {
		strings.write_string(&content, " &middot; ")
		write_html_escaped(&content, article.frontmatter.author)
	}
	write_tags(&content, article.frontmatter.tags[:], "../")
	strings.write_string(&content, "</div>\n")

	if article.frontmatter.toc {
		write_toc(&content, article.headings[:])
	}

	strings.write_string(&content, article.body_html)

	// Series navigation
	if len(article.frontmatter.series) > 0 && all_articles != nil {
		write_series_nav(&content, article, all_articles)
	}

	// Prev / Next navigation
	if prev != nil || next != nil {
		strings.write_string(&content, "<nav class=\"article-nav\">\n")
		if next != nil {
			strings.write_string(&content, "<a class=\"article-nav-prev\" href=\"")
			strings.write_string(&content, next.slug)
			strings.write_string(&content, ".html\">&larr; ")
			write_html_escaped(&content, next.frontmatter.title)
			strings.write_string(&content, "</a>\n")
		}
		if prev != nil {
			strings.write_string(&content, "<a class=\"article-nav-next\" href=\"")
			strings.write_string(&content, prev.slug)
			strings.write_string(&content, ".html\">")
			write_html_escaped(&content, prev.frontmatter.title)
			strings.write_string(&content, " &rarr;</a>\n")
		}
		strings.write_string(&content, "</nav>\n")
	}

	article_path := strings.concatenate({"articles/", article.slug, ".html"})
	render_page(&b, config, article.frontmatter.title, "articles.html", "../", strings.to_string(content), article.frontmatter.description, article_path)
	return strings.to_string(b)
}

// ---------------------------------------------------------------------------
// Projects Listing Page
// ---------------------------------------------------------------------------

render_projects_page :: proc(config: Site_Config, projects: []Project, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	content := strings.builder_make(allocator)

	strings.write_string(&content, "<h1>Projects</h1>\n<ul class=\"article-list\">\n")
	for project in projects {
		strings.write_string(&content, "<li><span class=\"date\">")
		strings.write_string(&content, project.frontmatter.date)
		strings.write_string(&content, "</span> <a href=\"projects/")
		strings.write_string(&content, project.slug)
		strings.write_string(&content, ".html\">")
		write_html_escaped(&content, project.frontmatter.title)
		strings.write_string(&content, "</a>")
		write_description(&content, project.frontmatter)
		strings.write_string(&content, "</li>\n")
	}
	strings.write_string(&content, "</ul>\n")

	render_page(&b, config, "Projects", "projects.html", "", strings.to_string(content), page_path = "projects.html")
	return strings.to_string(b)
}

// ---------------------------------------------------------------------------
// Individual Project Page
// ---------------------------------------------------------------------------

render_project_page :: proc(
	config: Site_Config,
	project: Project,
	allocator := context.allocator,
) -> string {
	b := strings.builder_make(allocator)
	content := strings.builder_make(allocator)

	// Project meta
	strings.write_string(&content, "<div class=\"article-meta\">")
	write_date(&content, project.frontmatter)
	if len(project.frontmatter.author) > 0 {
		strings.write_string(&content, " &middot; ")
		write_html_escaped(&content, project.frontmatter.author)
	}
	write_tags(&content, project.frontmatter.tags[:], "../")
	strings.write_string(&content, "</div>\n")

	if project.frontmatter.toc {
		write_toc(&content, project.headings[:])
	}

	strings.write_string(&content, project.body_html)

	project_path := strings.concatenate({"projects/", project.slug, ".html"})
	render_page(&b, config, project.frontmatter.title, "projects.html", "../", strings.to_string(content), project.frontmatter.description, project_path)
	return strings.to_string(b)
}

// ---------------------------------------------------------------------------
// About Page
// ---------------------------------------------------------------------------

render_tag_page :: proc(config: Site_Config, tag: string, articles: []Article, projects: []Project, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	content := strings.builder_make(allocator)

	strings.write_string(&content, "<h1>Tagged: ")
	write_html_escaped(&content, tag)
	strings.write_string(&content, "</h1>\n")

	if len(articles) > 0 {
		strings.write_string(&content, "<h2>Articles</h2>\n<ul class=\"article-list\">\n")
		for article in articles {
			strings.write_string(&content, "<li><span class=\"date\">")
			strings.write_string(&content, article.frontmatter.date)
			strings.write_string(&content, "</span> <a href=\"../articles/")
			strings.write_string(&content, article.slug)
			strings.write_string(&content, ".html\">")
			write_html_escaped(&content, article.frontmatter.title)
			strings.write_string(&content, "</a></li>\n")
		}
		strings.write_string(&content, "</ul>\n")
	}

	if len(projects) > 0 {
		strings.write_string(&content, "<h2>Projects</h2>\n<ul class=\"article-list\">\n")
		for project in projects {
			strings.write_string(&content, "<li><span class=\"date\">")
			strings.write_string(&content, project.frontmatter.date)
			strings.write_string(&content, "</span> <a href=\"../projects/")
			strings.write_string(&content, project.slug)
			strings.write_string(&content, ".html\">")
			write_html_escaped(&content, project.frontmatter.title)
			strings.write_string(&content, "</a></li>\n")
		}
		strings.write_string(&content, "</ul>\n")
	}

	render_page(&b, config, tag, "articles.html", "../", strings.to_string(content))
	return strings.to_string(b)
}

render_tags_index_page :: proc(config: Site_Config, tag_counts: []Tag_Count, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	content := strings.builder_make(allocator)

	strings.write_string(&content, "<h1>Tags</h1>\n<ul class=\"tag-list\">\n")
	for tc in tag_counts {
		strings.write_string(&content, `<li><a class="tag" href="`)
		strings.write_string(&content, slugify(tc.name, allocator))
		strings.write_string(&content, `.html">`)
		write_html_escaped(&content, tc.name)
		fmt.sbprintf(&content, `</a> <span class="count">(%d)</span></li>`, tc.count)
		strings.write_string(&content, "\n")
	}
	strings.write_string(&content, "</ul>\n")

	render_page(&b, config, "Tags", "articles.html", "../", strings.to_string(content), page_path = "tags/index.html")
	return strings.to_string(b)
}

// ---------------------------------------------------------------------------
// 404 Page
// ---------------------------------------------------------------------------

render_404_page :: proc(config: Site_Config, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	render_page(&b, config, "Not Found", "", "", "<h1>404</h1>\n<p>Page not found. <a href=\"index.html\">Go home</a>.</p>\n")
	return strings.to_string(b)
}

// ---------------------------------------------------------------------------
// About Page
// ---------------------------------------------------------------------------

render_about_page :: proc(config: Site_Config, about_html: string, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	render_page(&b, config, "About", "about.html", "", about_html, page_path = "about.html")
	return strings.to_string(b)
}
