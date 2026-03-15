package main

import "core:fmt"
import "core:strings"

// ---------------------------------------------------------------------------
// HTML Renderer
// ---------------------------------------------------------------------------

write_html_escaped :: proc(b: ^strings.Builder, s: string) {
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

// Convert heading text to a URL-safe slug for anchor IDs.
slugify :: proc(s: string, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	for ch in s {
		switch {
		case ch >= 'a' && ch <= 'z', ch >= '0' && ch <= '9':
			strings.write_byte(&b, u8(ch))
		case ch >= 'A' && ch <= 'Z':
			strings.write_byte(&b, u8(ch) + 32)
		case ch == ' ' || ch == '-' || ch == '_':
			strings.write_byte(&b, '-')
		}
	}
	return strings.to_string(b)
}

// Extract plain text from inlines (for heading text / slugs).
inlines_to_text :: proc(inlines: []Inline, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	for inl in inlines {
		switch v in inl {
		case Text:
			strings.write_string(&b, v.text)
		case Bold:
			strings.write_string(&b, inlines_to_text(v.children[:], allocator))
		case Italic:
			strings.write_string(&b, inlines_to_text(v.children[:], allocator))
		case Code_Span:
			strings.write_string(&b, v.text)
		case Link:
			strings.write_string(&b, v.text)
		case Image:
			strings.write_string(&b, v.alt)
		case Sidenote_Ref:
		}
	}
	return strings.to_string(b)
}

// Extract heading info from a document for TOC generation.
extract_headings :: proc(doc: Document, allocator := context.allocator) -> [dynamic]Heading_Info {
	headings := make([dynamic]Heading_Info, allocator)
	for block in doc.blocks {
		if h, ok := block.(Heading); ok && h.level <= 3 {
			text := inlines_to_text(h.inlines[:], allocator)
			append(&headings, Heading_Info{
				level = h.level,
				text  = text,
				id    = slugify(text, allocator),
			})
		}
	}
	return headings
}

Sidenote_Defs :: struct {
	labels:  [dynamic]string,
	inlines: [dynamic][dynamic]Inline,
}

sidenote_defs_lookup :: proc(defs: ^Sidenote_Defs, label: string) -> []Inline {
	if defs == nil {
		return nil
	}
	for l, i in defs.labels {
		if l == label {
			return defs.inlines[i][:]
		}
	}
	return nil
}

render_html :: proc(doc: Document, allocator := context.allocator) -> string {
	// Collect sidenote definitions
	sn_defs := Sidenote_Defs {
		labels  = make([dynamic]string, allocator),
		inlines = make([dynamic][dynamic]Inline, allocator),
	}
	for block in doc.blocks {
		if def, ok := block.(Sidenote_Def); ok {
			append(&sn_defs.labels, def.label)
			append(&sn_defs.inlines, def.inlines)
		}
	}

	headings := extract_headings(doc, allocator)

	b := strings.builder_make(allocator)
	sn_counter := 0
	h_counter := 0
	render_blocks(&b, doc.blocks[:], &sn_defs, &sn_counter, headings[:], &h_counter)
	return strings.to_string(b)
}

render_blocks :: proc(b: ^strings.Builder, blocks: []Block, sn_defs: ^Sidenote_Defs, sn_counter: ^int, headings: []Heading_Info, h_counter: ^int) {
	for block in blocks {
		switch v in block {
		case Heading:
			id := ""
			if v.level <= 3 && h_counter^ < len(headings) {
				id = headings[h_counter^].id
				h_counter^ += 1
			}
			fmt.sbprintf(b, `<h%d id="%s">`, v.level, id)
			render_inlines(b, v.inlines[:], sn_defs, sn_counter)
			fmt.sbprintf(b, ` <a href="#%s" class="anchor">#</a>`, id)
			fmt.sbprintf(b, "</h%d>\n", v.level)
		case Paragraph:
			strings.write_string(b, "<p>")
			render_inlines(b, v.inlines[:], sn_defs, sn_counter)
			strings.write_string(b, "</p>\n")
		case Code_Block:
			if len(v.language) > 0 {
				strings.write_string(b, "<pre><code class=\"language-")
				write_html_escaped(b, v.language)
				strings.write_string(b, "\">")
			} else {
				strings.write_string(b, "<pre><code>")
			}
			highlight_code(b, v.language, v.code)
			strings.write_string(b, "</code></pre>\n")
		case Unordered_List:
			strings.write_string(b, "<ul>\n")
			for item in v.items {
				strings.write_string(b, "<li>")
				render_inlines(b, item[:], sn_defs, sn_counter)
				strings.write_string(b, "</li>\n")
			}
			strings.write_string(b, "</ul>\n")
		case Ordered_List:
			strings.write_string(b, "<ol>\n")
			for item in v.items {
				strings.write_string(b, "<li>")
				render_inlines(b, item[:], sn_defs, sn_counter)
				strings.write_string(b, "</li>\n")
			}
			strings.write_string(b, "</ol>\n")
		case Blockquote:
			strings.write_string(b, "<blockquote><p>")
			render_inlines(b, v.inlines[:], sn_defs, sn_counter)
			strings.write_string(b, "</p></blockquote>\n")
		case Horizontal_Rule:
			strings.write_string(b, "<hr>\n")
		case Sidenote_Def:
			// Consumed during pre-pass; not rendered as a block
		}
	}
}

render_inlines :: proc(b: ^strings.Builder, inlines: []Inline, sn_defs: ^Sidenote_Defs, sn_counter: ^int) {
	for inl in inlines {
		switch v in inl {
		case Text:
			write_html_escaped(b, v.text)
		case Bold:
			strings.write_string(b, "<strong>")
			render_inlines(b, v.children[:], sn_defs, sn_counter)
			strings.write_string(b, "</strong>")
		case Italic:
			strings.write_string(b, "<em>")
			render_inlines(b, v.children[:], sn_defs, sn_counter)
			strings.write_string(b, "</em>")
		case Code_Span:
			strings.write_string(b, "<code>")
			write_html_escaped(b, v.text)
			strings.write_string(b, "</code>")
		case Link:
			strings.write_string(b, "<a href=\"")
			write_html_escaped(b, v.url)
			strings.write_string(b, "\">")
			write_html_escaped(b, v.text)
			strings.write_string(b, "</a>")
		case Image:
			strings.write_string(b, "<figure><img src=\"")
			write_html_escaped(b, v.url)
			strings.write_string(b, "\" alt=\"")
			write_html_escaped(b, v.alt)
			strings.write_string(b, "\" loading=\"lazy\">")
			if len(v.alt) > 0 {
				strings.write_string(b, "<figcaption>")
				write_html_escaped(b, v.alt)
				strings.write_string(b, "</figcaption>")
			}
			strings.write_string(b, "</figure>")
		case Sidenote_Ref:
			sn_counter^ += 1
			n := sn_counter^
			sn_inlines := sidenote_defs_lookup(sn_defs, v.label)
			fmt.sbprintf(b, `<label for="sn-%d" class="sn-num">%d</label>`, n, n)
			fmt.sbprintf(b, `<input type="checkbox" id="sn-%d" class="sn-check">`, n)
			fmt.sbprintf(b, `<span class="sn"><span class="sn-num">%d</span> `, n)
			render_inlines(b, sn_inlines, sn_defs, sn_counter)
			strings.write_string(b, "</span>")
		}
	}
}
