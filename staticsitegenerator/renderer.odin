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

// Write plain text from inlines into a builder (for heading text / slugs).
inlines_to_text_builder :: proc(b: ^strings.Builder, inlines: []Inline) {
	for inl in inlines {
		switch v in inl {
		case Text:
			strings.write_string(b, v.text)
		case Bold:
			inlines_to_text_builder(b, v.children[:])
		case Italic:
			inlines_to_text_builder(b, v.children[:])
		case Code_Span:
			strings.write_string(b, v.text)
		case Link:
			strings.write_string(b, v.text)
		case Image:
			strings.write_string(b, v.alt)
		case Sidenote_Ref:
		}
	}
}

// Extract plain text from inlines as a string.
inlines_to_text :: proc(inlines: []Inline, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	inlines_to_text_builder(&b, inlines)
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

Sidenote_Defs :: map[string][dynamic]Inline

Render_State :: struct {
	b:          ^strings.Builder,
	sn_defs:    Sidenote_Defs,
	sn_counter: int,
	headings:   []Heading_Info,
	h_counter:  int,
}

render_html :: proc(doc: Document, headings: []Heading_Info, allocator := context.allocator) -> string {
	// Collect sidenote definitions
	sn_defs := make(Sidenote_Defs, allocator = context.temp_allocator)
	for block in doc.blocks {
		if def, ok := block.(Sidenote_Def); ok {
			sn_defs[def.label] = def.inlines
		}
	}

	b := strings.builder_make(allocator)
	rs := Render_State {
		b        = &b,
		sn_defs  = sn_defs,
		headings = headings,
	}
	render_blocks(&rs, doc.blocks[:])
	return strings.to_string(b)
}

render_blocks :: proc(rs: ^Render_State, blocks: []Block) {
	for block in blocks {
		switch v in block {
		case Heading:
			id := ""
			if v.level <= 3 && rs.h_counter < len(rs.headings) {
				id = rs.headings[rs.h_counter].id
				rs.h_counter += 1
			}
			if len(id) > 0 {
				fmt.sbprintf(rs.b, `<h%d id="%s">`, v.level, id)
			} else {
				fmt.sbprintf(rs.b, "<h%d>", v.level)
			}
			render_inlines(rs, v.inlines[:])
			if len(id) > 0 {
				fmt.sbprintf(rs.b, ` <a href="#%s" class="anchor">#</a>`, id)
			}
			fmt.sbprintf(rs.b, "</h%d>\n", v.level)
		case Paragraph:
			strings.write_string(rs.b, "<p>")
			render_inlines(rs, v.inlines[:])
			strings.write_string(rs.b, "</p>\n")
		case Code_Block:
			if len(v.language) > 0 {
				strings.write_string(rs.b, "<pre><code class=\"language-")
				write_html_escaped(rs.b, v.language)
				strings.write_string(rs.b, "\">")
			} else {
				strings.write_string(rs.b, "<pre><code>")
			}
			highlight_code(rs.b, v.language, v.code)
			strings.write_string(rs.b, "</code></pre>\n")
		case List:
			strings.write_string(rs.b, "<ol>\n" if v.ordered else "<ul>\n")
			for item in v.items {
				strings.write_string(rs.b, "<li>")
				render_inlines(rs, item[:])
				strings.write_string(rs.b, "</li>\n")
			}
			strings.write_string(rs.b, "</ol>\n" if v.ordered else "</ul>\n")
		case Blockquote:
			strings.write_string(rs.b, "<blockquote><p>")
			render_inlines(rs, v.inlines[:])
			strings.write_string(rs.b, "</p></blockquote>\n")
		case Horizontal_Rule:
			strings.write_string(rs.b, "<hr>\n")
		case Sidenote_Def:
			// Consumed during pre-pass; not rendered as a block
		}
	}
}

render_inlines :: proc(rs: ^Render_State, inlines: []Inline) {
	for inl in inlines {
		switch v in inl {
		case Text:
			write_html_escaped(rs.b, v.text)
		case Bold:
			strings.write_string(rs.b, "<strong>")
			render_inlines(rs, v.children[:])
			strings.write_string(rs.b, "</strong>")
		case Italic:
			strings.write_string(rs.b, "<em>")
			render_inlines(rs, v.children[:])
			strings.write_string(rs.b, "</em>")
		case Code_Span:
			strings.write_string(rs.b, "<code>")
			write_html_escaped(rs.b, v.text)
			strings.write_string(rs.b, "</code>")
		case Link:
			strings.write_string(rs.b, "<a href=\"")
			write_html_escaped(rs.b, v.url)
			strings.write_string(rs.b, "\">")
			write_html_escaped(rs.b, v.text)
			strings.write_string(rs.b, "</a>")
		case Image:
			strings.write_string(rs.b, "<figure><img src=\"")
			write_html_escaped(rs.b, v.url)
			strings.write_string(rs.b, "\" alt=\"")
			write_html_escaped(rs.b, v.alt)
			strings.write_string(rs.b, "\" loading=\"lazy\">")
			if len(v.alt) > 0 {
				strings.write_string(rs.b, "<figcaption>")
				write_html_escaped(rs.b, v.alt)
				strings.write_string(rs.b, "</figcaption>")
			}
			strings.write_string(rs.b, "</figure>")
		case Sidenote_Ref:
			rs.sn_counter += 1
			n := rs.sn_counter
			sn_inlines: []Inline
			if found, ok := rs.sn_defs[v.label]; ok {
				sn_inlines = found[:]
			}
			fmt.sbprintf(rs.b, `<label for="sn-%d" class="sn-num">%d</label>`, n, n)
			fmt.sbprintf(rs.b, `<input type="checkbox" id="sn-%d" class="sn-check">`, n)
			fmt.sbprintf(rs.b, `<span class="sn"><span class="sn-num">%d</span> `, n)
			render_inlines(rs, sn_inlines)
			strings.write_string(rs.b, "</span>")
		}
	}
}
