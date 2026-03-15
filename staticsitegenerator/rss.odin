package main

import "core:strings"
import "core:time"

// ---------------------------------------------------------------------------
// RSS 2.0 Feed
// ---------------------------------------------------------------------------

render_rss_feed :: proc(config: Site_Config, articles: []Article, projects: []Project, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)

	strings.write_string(&b, `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
<channel>
<title>`)
	write_html_escaped(&b, config.site_title)
	strings.write_string(&b, "</title>\n<link>")
	write_html_escaped(&b, config.site_url)
	strings.write_string(&b, "</link>\n<description>")
	write_html_escaped(&b, config.description)
	strings.write_string(&b, "</description>\n")
	strings.write_string(&b, `<atom:link href="`)
	write_html_escaped(&b, config.site_url)
	strings.write_string(&b, `/feed.xml" rel="self" type="application/rss+xml"/>`)
	strings.write_string(&b, "\n<lastBuildDate>")
	strings.write_string(&b, format_rss_now(allocator))
	strings.write_string(&b, "</lastBuildDate>\n")

	for article in articles {
		write_rss_item(&b, config, article, "articles", allocator)
	}
	for project in projects {
		write_rss_item(&b, config, project, "projects", allocator)
	}

	strings.write_string(&b, "</channel>\n</rss>\n")
	return strings.to_string(b)
}

write_rss_item :: proc(b: ^strings.Builder, config: Site_Config, item: Content_Item, section: string, allocator := context.allocator) {
	item_url := strings.concatenate({config.site_url, "/", section, "/", item.slug, ".html"}, allocator)
	strings.write_string(b, "<item>\n<title>")
	write_html_escaped(b, item.frontmatter.title)
	strings.write_string(b, "</title>\n<link>")
	write_html_escaped(b, item_url)
	strings.write_string(b, "</link>\n<guid>")
	write_html_escaped(b, item_url)
	strings.write_string(b, "</guid>\n<pubDate>")
	strings.write_string(b, format_rss_date(item.frontmatter.date, allocator))
	strings.write_string(b, "</pubDate>\n<description>")
	desc := item.frontmatter.description if len(item.frontmatter.description) > 0 else item.frontmatter.title
	write_html_escaped(b, desc)
	strings.write_string(b, "</description>\n</item>\n")
}

format_rss_now :: proc(allocator := context.allocator) -> string {
	return format_rss_time(time.now(), allocator)
}

// ---------------------------------------------------------------------------
// Sitemap
// ---------------------------------------------------------------------------

render_sitemap :: proc(config: Site_Config, articles: []Article, projects: []Project, tags: []string, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)

	strings.write_string(&b, `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
`)

	write_sitemap_url :: proc(b: ^strings.Builder, base: string, path: string, lastmod: string = "") {
		strings.write_string(b, "<url><loc>")
		write_html_escaped(b, base)
		strings.write_string(b, "/")
		strings.write_string(b, path)
		strings.write_string(b, "</loc>")
		if len(lastmod) > 0 {
			strings.write_string(b, "<lastmod>")
			strings.write_string(b, lastmod)
			strings.write_string(b, "</lastmod>")
		}
		strings.write_string(b, "</url>\n")
	}

	write_sitemap_url(&b, config.site_url, "index.html")
	write_sitemap_url(&b, config.site_url, "articles.html")
	write_sitemap_url(&b, config.site_url, "projects.html")
	write_sitemap_url(&b, config.site_url, "about.html")

	for article in articles {
		path := strings.concatenate({"articles/", article.slug, ".html"}, allocator)
		date := article.frontmatter.modified if len(article.frontmatter.modified) > 0 else article.frontmatter.date
		write_sitemap_url(&b, config.site_url, path, date)
	}

	for project in projects {
		path := strings.concatenate({"projects/", project.slug, ".html"}, allocator)
		date := project.frontmatter.modified if len(project.frontmatter.modified) > 0 else project.frontmatter.date
		write_sitemap_url(&b, config.site_url, path, date)
	}

	for tag in tags {
		path := strings.concatenate({"tags/", slugify(tag, allocator), ".html"}, allocator)
		write_sitemap_url(&b, config.site_url, path)
	}

	strings.write_string(&b, "</urlset>\n")
	return strings.to_string(b)
}
