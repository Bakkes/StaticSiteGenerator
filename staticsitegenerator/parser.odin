package main

import "core:strings"

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

is_blank_line :: proc(line: string) -> bool {
	s := scanner_make(line)
	is_space :: proc(c: byte) -> bool { return c == ' ' || c == '\t' || c == '\r' }
	scanner_capture_while(&s, is_space)
	return scanner_at_end(&s)
}

is_hr_line :: proc(line: string) -> bool {
	trimmed := strings.trim_space(line)
	if len(trimmed) < 3 {
		return false
	}
	ch := trimmed[0]
	if ch != '-' && ch != '*' && ch != '_' {
		return false
	}
	for i in 0 ..< len(trimmed) {
		if trimmed[i] != ch && trimmed[i] != ' ' {
			return false
		}
	}
	return true
}

heading_level :: proc(line: string) -> int {
	s := scanner_make(line)
	is_hash :: proc(c: byte) -> bool { return c == '#' }
	hashes := scanner_capture_while(&s, is_hash)
	level := len(hashes)
	if level >= 1 && level <= 6 && scanner_match_byte(&s, ' ') {
		return level
	}
	return 0
}

starts_with_fence :: proc(line: string) -> bool {
	trimmed := strings.trim_left_space(line)
	s := scanner_make(trimmed)
	return scanner_check_prefix(&s, "```")
}

fence_language :: proc(line: string) -> string {
	trimmed := strings.trim_left_space(line)
	s := scanner_make(trimmed)
	is_backtick :: proc(c: byte) -> bool { return c == '`' }
	scanner_capture_while(&s, is_backtick)
	return strings.trim_space(scanner_rest(&s))
}

is_unordered_item :: proc(line: string) -> (content: string, ok: bool) {
	s := scanner_make(line)
	ch, has := scanner_peek(&s)
	if has && (ch == '-' || ch == '*' || ch == '+') {
		scanner_advance(&s)
		if scanner_match_byte(&s, ' ') {
			return scanner_rest(&s), true
		}
	}
	return "", false
}

is_ordered_item :: proc(line: string) -> (content: string, ok: bool) {
	s := scanner_make(line)
	is_digit :: proc(c: byte) -> bool { return c >= '0' && c <= '9' }
	digits := scanner_capture_while(&s, is_digit)
	if len(digits) > 0 && scanner_match_prefix(&s, ". ") {
		return scanner_rest(&s), true
	}
	return "", false
}

is_blockquote_line :: proc(line: string) -> (content: string, ok: bool) {
	s := scanner_make(line)
	if scanner_match_byte(&s, '>') {
		scanner_match_byte(&s, ' ')
		return scanner_rest(&s), true
	}
	return "", false
}

// ---------------------------------------------------------------------------
// Inline Parser
// ---------------------------------------------------------------------------

parse_inlines :: proc(src: string, allocator := context.allocator) -> [dynamic]Inline {
	result := make([dynamic]Inline, allocator)
	s := scanner_make(src)

	flush :: proc(result: ^[dynamic]Inline, s: ^Text_Scanner) {
		text := scanner_flush_text(s)
		if len(text) > 0 {
			append(result, Inline(Text{text = text}))
		}
	}

	for !scanner_at_end(&s) {
		ch, _ := scanner_peek(&s)

		// Inline code: `...`
		if ch == '`' {
			flush(&result, &s)
			scanner_advance(&s)
			code_text, ok := scanner_capture_until(&s, '`')
			if ok {
				append(&result, Inline(Code_Span{text = code_text}))
				scanner_reset_mark(&s)
				continue
			}
			s.pos = s.mark
			scanner_advance(&s)
			continue
		}

		// Image: ![alt](url)
		if ch == '!' {
			ch2, has2 := scanner_peek(&s, 1)
			if has2 && ch2 == '[' {
				flush(&result, &s)
				scanner_advance(&s, 2)
				alt, ok1 := scanner_capture_until(&s, ']')
				if ok1 && scanner_match_byte(&s, '(') {
					url, ok2 := scanner_capture_until(&s, ')')
					if ok2 {
						append(&result, Inline(Image{alt = alt, url = url}))
						scanner_reset_mark(&s)
						continue
					}
				}
				s.pos = s.mark
				scanner_advance(&s)
				continue
			}
		}

		// Sidenote ref [^label] and Link [text](url) both start with [
		if ch == '[' {
			// Try sidenote ref: [^label]
			ch2, has2 := scanner_peek(&s, 1)
			if has2 && ch2 == '^' {
				saved := s.pos
				scanner_advance(&s, 2)
				label, ok := scanner_capture_until(&s, ']')
				if ok {
					next, has_next := scanner_peek(&s)
					if !has_next || next != '(' {
						if saved > s.mark {
							append(&result, Inline(Text{text = s.src[s.mark:saved]}))
						}
						append(&result, Inline(Sidenote_Ref{label = label}))
						s.mark = s.pos
						continue
					}
				}
				s.pos = saved
			}

			// Link: [text](url)
			flush(&result, &s)
			scanner_advance(&s)
			link_text, ok1 := scanner_capture_until(&s, ']')
			if ok1 && scanner_match_byte(&s, '(') {
				url, ok2 := scanner_capture_until(&s, ')')
				if ok2 {
					append(&result, Inline(Link{text = link_text, url = url}))
					scanner_reset_mark(&s)
					continue
				}
			}
			s.pos = s.mark
			scanner_advance(&s)
			continue
		}

		// Bold: **...**
		if ch == '*' {
			ch2, has2 := scanner_peek(&s, 1)
			if has2 && ch2 == '*' {
				flush(&result, &s)
				scanner_advance(&s, 2)
				inner, ok := scanner_capture_until_str(&s, "**")
				if ok {
					children := parse_inlines(inner, allocator)
					append(&result, Inline(Bold{children = children}))
					scanner_reset_mark(&s)
					continue
				}
				s.pos = s.mark
				scanner_advance(&s)
				continue
			}

			// Italic: *...*
			flush(&result, &s)
			scanner_advance(&s)
			inner, ok := scanner_capture_until(&s, '*')
			if ok {
				children := parse_inlines(inner, allocator)
				append(&result, Inline(Italic{children = children}))
				scanner_reset_mark(&s)
				continue
			}
			s.pos = s.mark
			scanner_advance(&s)
			continue
		}

		scanner_advance(&s)
	}

	flush(&result, &s)
	return result
}

// ---------------------------------------------------------------------------
// Block Parser
// ---------------------------------------------------------------------------

parse_markdown :: proc(source: string, allocator := context.allocator) -> Document {
	doc := Document {
		blocks = make([dynamic]Block, allocator),
	}

	lines := strings.split_lines(source, allocator)

	i := 0
	for i < len(lines) {
		line := lines[i]

		// Sidenote definition: [^label]: text
		if len(line) >= 5 {
			ls := scanner_make(line)
			if scanner_match_prefix(&ls, "[^") {
				label, ok := scanner_capture_until(&ls, ']')
				if ok && scanner_match_prefix(&ls, ": ") {
					inlines := parse_inlines(scanner_rest(&ls), allocator)
					append(&doc.blocks, Block(Sidenote_Def{label = label, inlines = inlines}))
					i += 1
					continue
				}
			}
		}

		if is_blank_line(line) {
			i += 1
			continue
		}

		if starts_with_fence(line) {
			lang := fence_language(line)
			code_start := i + 1
			code_end := code_start
			for code_end < len(lines) {
				if starts_with_fence(lines[code_end]) {
					break
				}
				code_end += 1
			}
			code := strings.join(lines[code_start:code_end], "\n", allocator)
			append(&doc.blocks, Block(Code_Block{language = lang, code = code}))
			i = code_end + 1 if code_end < len(lines) else code_end
			continue
		}

		level := heading_level(line)
		if level > 0 {
			content := line[level + 1:]
			inlines := parse_inlines(content, allocator)
			append(&doc.blocks, Block(Heading{level = level, inlines = inlines}))
			i += 1
			continue
		}

		if is_hr_line(line) {
			append(&doc.blocks, Block(Horizontal_Rule{}))
			i += 1
			continue
		}

		if _, ok := is_unordered_item(line); ok {
			list := Unordered_List {
				items = make([dynamic][dynamic]Inline, allocator),
			}
			for i < len(lines) {
				content, item_ok := is_unordered_item(lines[i])
				if !item_ok {
					break
				}
				append(&list.items, parse_inlines(content, allocator))
				i += 1
			}
			append(&doc.blocks, Block(list))
			continue
		}

		if _, ok := is_ordered_item(line); ok {
			list := Ordered_List {
				items = make([dynamic][dynamic]Inline, allocator),
			}
			for i < len(lines) {
				content, item_ok := is_ordered_item(lines[i])
				if !item_ok {
					break
				}
				append(&list.items, parse_inlines(content, allocator))
				i += 1
			}
			append(&doc.blocks, Block(list))
			continue
		}

		if _, ok := is_blockquote_line(line); ok {
			bq_parts := make([dynamic]string, allocator)
			defer delete(bq_parts)
			for i < len(lines) {
				content, bq_ok := is_blockquote_line(lines[i])
				if !bq_ok {
					break
				}
				append(&bq_parts, content)
				i += 1
			}
			joined := strings.join(bq_parts[:], " ", allocator)
			inlines := parse_inlines(joined, allocator)
			append(&doc.blocks, Block(Blockquote{inlines = inlines}))
			continue
		}

		{
			para_parts := make([dynamic]string, allocator)
			defer delete(para_parts)
			for i < len(lines) && !is_blank_line(lines[i]) {
				l := lines[i]
				if starts_with_fence(l) {break}
				if heading_level(l) > 0 {break}
				if is_hr_line(l) {break}
				if _, ok := is_unordered_item(l); ok {break}
				if _, ok := is_ordered_item(l); ok {break}
				if _, ok := is_blockquote_line(l); ok {break}
				if len(l) >= 5 {
					ls := scanner_make(l)
					if scanner_match_prefix(&ls, "[^") {
						_, ok := scanner_capture_until(&ls, ']')
						if ok && scanner_check_prefix(&ls, ": ") {
							break
						}
					}
				}
				append(&para_parts, l)
				i += 1
			}
			if len(para_parts) > 0 {
				joined := strings.join(para_parts[:], " ", allocator)
				inlines := parse_inlines(joined, allocator)
				append(&doc.blocks, Block(Paragraph{inlines = inlines}))
			}
		}
	}

	return doc
}
