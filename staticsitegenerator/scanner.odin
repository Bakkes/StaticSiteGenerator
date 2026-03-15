package main

import "core:strings"

Text_Scanner :: struct {
	src:  string,
	pos:  int,
	mark: int,
}

scanner_make :: proc(src: string) -> Text_Scanner {
	return Text_Scanner{src = src, pos = 0, mark = 0}
}

scanner_at_end :: proc(s: ^Text_Scanner) -> bool {
	return s.pos >= len(s.src)
}

scanner_peek :: proc(s: ^Text_Scanner, offset := 0) -> (byte, bool) {
	idx := s.pos + offset
	if idx >= 0 && idx < len(s.src) {
		return s.src[idx], true
	}
	return 0, false
}

scanner_advance :: proc(s: ^Text_Scanner, n := 1) {
	s.pos += n
	if s.pos > len(s.src) {
		s.pos = len(s.src)
	}
}

scanner_rest :: proc(s: ^Text_Scanner) -> string {
	if s.pos >= len(s.src) {
		return ""
	}
	return s.src[s.pos:]
}

scanner_check_prefix :: proc(s: ^Text_Scanner, prefix: string) -> bool {
	return strings.has_prefix(s.src[s.pos:], prefix) if s.pos < len(s.src) else false
}

scanner_match_byte :: proc(s: ^Text_Scanner, c: byte) -> bool {
	if s.pos < len(s.src) && s.src[s.pos] == c {
		s.pos += 1
		return true
	}
	return false
}

scanner_match_prefix :: proc(s: ^Text_Scanner, prefix: string) -> bool {
	if scanner_check_prefix(s, prefix) {
		s.pos += len(prefix)
		return true
	}
	return false
}

scanner_capture_until :: proc(s: ^Text_Scanner, c: byte) -> (string, bool) {
	start := s.pos
	for s.pos < len(s.src) {
		if s.src[s.pos] == c {
			captured := s.src[start:s.pos]
			s.pos += 1 // consume the delimiter
			return captured, true
		}
		s.pos += 1
	}
	s.pos = start // restore on failure
	return "", false
}

scanner_capture_until_str :: proc(s: ^Text_Scanner, target: string) -> (string, bool) {
	start := s.pos
	for s.pos + len(target) <= len(s.src) {
		if s.src[s.pos:][:len(target)] == target {
			captured := s.src[start:s.pos]
			s.pos += len(target) // consume the delimiter
			return captured, true
		}
		s.pos += 1
	}
	s.pos = start // restore on failure
	return "", false
}

scanner_capture_while :: proc(s: ^Text_Scanner, pred: proc(byte) -> bool) -> string {
	start := s.pos
	for s.pos < len(s.src) && pred(s.src[s.pos]) {
		s.pos += 1
	}
	return s.src[start:s.pos]
}

scanner_flush_text :: proc(s: ^Text_Scanner) -> string {
	text := s.src[s.mark:s.pos]
	s.mark = s.pos
	return text
}

scanner_reset_mark :: proc(s: ^Text_Scanner) {
	s.mark = s.pos
}
