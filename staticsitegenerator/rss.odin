package main

import "core:strings"
import "core:time"
import "core:strconv"

// ---------------------------------------------------------------------------
// RSS 2.0 Feed
// ---------------------------------------------------------------------------

render_rss_feed :: proc(config: Site_Config, articles: []Article, projects: []Project, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)

	strings.write_string(&b, `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
<channel>
<title>`)
	write_xml_escaped(&b, config.site_title)
	strings.write_string(&b, "</title>\n<link>")
	write_xml_escaped(&b, config.site_url)
	strings.write_string(&b, "</link>\n<description>")
	write_xml_escaped(&b, config.description)
	strings.write_string(&b, "</description>\n")
	strings.write_string(&b, `<atom:link href="`)
	write_xml_escaped(&b, config.site_url)
	strings.write_string(&b, `/feed.xml" rel="self" type="application/rss+xml"/>`)
	strings.write_string(&b, "\n<lastBuildDate>")
	strings.write_string(&b, format_rss_now(allocator))
	strings.write_string(&b, "</lastBuildDate>\n")

	for article in articles {
		strings.write_string(&b, "<item>\n<title>")
		write_xml_escaped(&b, article.frontmatter.title)
		strings.write_string(&b, "</title>\n<link>")
		write_xml_escaped(&b, config.site_url)
		strings.write_string(&b, "/articles/")
		strings.write_string(&b, article.slug)
		strings.write_string(&b, ".html</link>\n<guid>")
		write_xml_escaped(&b, config.site_url)
		strings.write_string(&b, "/articles/")
		strings.write_string(&b, article.slug)
		strings.write_string(&b, ".html</guid>\n<pubDate>")
		strings.write_string(&b, format_rss_date(article.frontmatter.date, allocator))
		strings.write_string(&b, "</pubDate>\n<description>")
		desc := article.frontmatter.description if len(article.frontmatter.description) > 0 else article.frontmatter.title
		write_xml_escaped(&b, desc)
		strings.write_string(&b, "</description>\n</item>\n")
	}

	for project in projects {
		strings.write_string(&b, "<item>\n<title>")
		write_xml_escaped(&b, project.frontmatter.title)
		strings.write_string(&b, "</title>\n<link>")
		write_xml_escaped(&b, config.site_url)
		strings.write_string(&b, "/projects/")
		strings.write_string(&b, project.slug)
		strings.write_string(&b, ".html</link>\n<guid>")
		write_xml_escaped(&b, config.site_url)
		strings.write_string(&b, "/projects/")
		strings.write_string(&b, project.slug)
		strings.write_string(&b, ".html</guid>\n<pubDate>")
		strings.write_string(&b, format_rss_date(project.frontmatter.date, allocator))
		strings.write_string(&b, "</pubDate>\n<description>")
		desc := project.frontmatter.description if len(project.frontmatter.description) > 0 else project.frontmatter.title
		write_xml_escaped(&b, desc)
		strings.write_string(&b, "</description>\n</item>\n")
	}

	strings.write_string(&b, "</channel>\n</rss>\n")
	return strings.to_string(b)
}

format_rss_now :: proc(allocator := context.allocator) -> string {
	now := time.now()
	wd := time.weekday(now)
	year, month, day := time.date(now)
	hour, min, sec := time.clock_from_time(now)

	day_names := [7]string{"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}
	month_names := [12]string{"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

	b := strings.builder_make(allocator)
	strings.write_string(&b, day_names[wd])
	strings.write_string(&b, ", ")

	buf: [20]byte
	if day < 10 {
		strings.write_byte(&b, '0')
	}
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
		write_xml_escaped(b, base)
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

write_xml_escaped :: proc(b: ^strings.Builder, s: string) {
	start := 0
	for i in 0 ..< len(s) {
		esc: string
		switch s[i] {
		case '<':
			esc = "&lt;"
		case '>':
			esc = "&gt;"
		case '&':
			esc = "&amp;"
		case '"':
			esc = "&quot;"
		case '\'':
			esc = "&apos;"
		case:
			continue
		}
		if i > start {
			strings.write_string(b, s[start:i])
		}
		strings.write_string(b, esc)
		start = i + 1
	}
	if start < len(s) {
		strings.write_string(b, s[start:])
	}
}
