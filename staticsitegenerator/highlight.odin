package main

import "core:strings"

// ---------------------------------------------------------------------------
// Syntax Highlighting — build-time tokenizer
// ---------------------------------------------------------------------------

Lang_Config :: struct {
	keywords:                 []string,
	line_comment:             string,
	block_comment_open:       string,
	block_comment_close:      string,
	has_triple_strings:       bool,
	has_backtick_strings:     bool,
	has_raw_strings:          bool,
	has_preprocessor:         bool,
	has_single_quote_strings: bool,
}

// ---- keyword lists --------------------------------------------------------

@(rodata)
PYTHON_KEYWORDS := [?]string{
	"False", "None", "True", "and", "as", "assert", "async", "await",
	"break", "class", "continue", "def", "del", "elif", "else", "except",
	"finally", "for", "from", "global", "if", "import", "in", "is",
	"lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try",
	"while", "with", "yield",
}

@(rodata)
C_KEYWORDS := [?]string{
	"auto", "break", "case", "char", "const", "continue", "default", "do",
	"double", "else", "enum", "extern", "float", "for", "goto", "if",
	"inline", "int", "long", "register", "return", "short", "signed",
	"sizeof", "static", "struct", "switch", "typedef", "union", "unsigned",
	"void", "volatile", "while",
	// C++ extras
	"bool", "catch", "class", "const_cast", "constexpr", "delete",
	"dynamic_cast", "explicit", "export", "false", "friend", "mutable",
	"namespace", "new", "noexcept", "nullptr", "operator", "override",
	"private", "protected", "public", "reinterpret_cast", "static_assert",
	"static_cast", "template", "this", "throw", "true", "try", "typeid",
	"typename", "using", "virtual",
}

@(rodata)
JS_KEYWORDS := [?]string{
	"async", "await", "break", "case", "catch", "class", "const",
	"continue", "debugger", "default", "delete", "do", "else", "export",
	"extends", "false", "finally", "for", "function", "if", "import",
	"in", "instanceof", "let", "new", "null", "of", "return", "super",
	"switch", "this", "throw", "true", "try", "typeof", "undefined",
	"var", "void", "while", "with", "yield",
}

@(rodata)
ODIN_KEYWORDS := [?]string{
	"auto_cast", "bit_set", "break", "case", "cast", "context",
	"continue", "defer", "distinct", "do", "dynamic", "else", "enum",
	"fallthrough", "for", "foreign", "if", "import", "in", "map",
	"matrix", "not_in", "or_else", "or_return", "package", "proc",
	"return", "struct", "switch", "transmute", "typeid", "union", "using",
	"when", "where",
	// built-in types
	"bool", "byte", "int", "uint", "uintptr", "i8", "i16", "i32", "i64",
	"i128", "u8", "u16", "u32", "u64", "u128", "f16", "f32", "f64",
	"complex32", "complex64", "complex128", "string", "cstring", "rawptr",
	"rune", "any", "typeid",
	// built-in values
	"true", "false", "nil",
}

// ---- language configs -----------------------------------------------------

LANG_PYTHON := Lang_Config {
	keywords                 = PYTHON_KEYWORDS[:],
	line_comment             = "#",
	has_triple_strings       = true,
	has_single_quote_strings = true,
}

LANG_C := Lang_Config {
	keywords            = C_KEYWORDS[:],
	line_comment        = "//",
	block_comment_open  = "/*",
	block_comment_close = "*/",
	has_preprocessor    = true,
}

LANG_JS := Lang_Config {
	keywords                 = JS_KEYWORDS[:],
	line_comment             = "//",
	block_comment_open       = "/*",
	block_comment_close      = "*/",
	has_backtick_strings     = true,
	has_single_quote_strings = true,
}

LANG_ODIN := Lang_Config {
	keywords            = ODIN_KEYWORDS[:],
	line_comment        = "//",
	block_comment_open  = "/*",
	block_comment_close = "*/",
	has_raw_strings     = true,
}

get_lang_config :: proc(language: string) -> (Lang_Config, bool) {
	switch language {
	case "python", "py":
		return LANG_PYTHON, true
	case "c", "cpp", "c++", "h", "hpp":
		return LANG_C, true
	case "javascript", "js", "typescript", "ts":
		return LANG_JS, true
	case "odin":
		return LANG_ODIN, true
	}
	return {}, false
}

// ---- helpers --------------------------------------------------------------

is_ident_byte :: proc(c: byte) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'
}

scan_number :: proc(s: ^Text_Scanner) {
	// hex prefix
	if scanner_check_prefix(s, "0x") || scanner_check_prefix(s, "0X") {
		scanner_advance(s, 2)
		is_hex :: proc(c: byte) -> bool {
			return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F') || c == '_'
		}
		scanner_capture_while(s, is_hex)
		return
	}
	// binary prefix
	if scanner_check_prefix(s, "0b") || scanner_check_prefix(s, "0B") {
		scanner_advance(s, 2)
		is_bin :: proc(c: byte) -> bool { return c == '0' || c == '1' || c == '_' }
		scanner_capture_while(s, is_bin)
		return
	}
	// octal prefix
	if scanner_check_prefix(s, "0o") || scanner_check_prefix(s, "0O") {
		scanner_advance(s, 2)
		is_oct :: proc(c: byte) -> bool { return c >= '0' && c <= '7' }
		scanner_capture_while(s, is_oct)
		return
	}
	// decimal + optional dot + optional exponent
	is_dec :: proc(c: byte) -> bool { return (c >= '0' && c <= '9') || c == '_' }
	scanner_capture_while(s, is_dec)
	// optional dot
	dot, has_dot := scanner_peek(s)
	if has_dot && dot == '.' {
		next, has_next := scanner_peek(s, 1)
		if has_next && next >= '0' && next <= '9' {
			scanner_advance(s)
			scanner_capture_while(s, is_dec)
		}
	}
	// optional exponent
	exp, has_exp := scanner_peek(s)
	if has_exp && (exp == 'e' || exp == 'E') {
		scanner_advance(s)
		sign, has_sign := scanner_peek(s)
		if has_sign && (sign == '+' || sign == '-') {
			scanner_advance(s)
		}
		is_digit :: proc(c: byte) -> bool { return c >= '0' && c <= '9' }
		scanner_capture_while(s, is_digit)
	}
}

is_keyword :: proc(config: Lang_Config, word: string) -> bool {
	for kw in config.keywords {
		if kw == word {
			return true
		}
	}
	return false
}

write_token :: proc(b: ^strings.Builder, class: string, text: string) {
	strings.write_string(b, "<span class=\"")
	strings.write_string(b, class)
	strings.write_string(b, "\">")
	write_html_escaped(b, text)
	strings.write_string(b, "</span>")
}

// ---- main entry point -----------------------------------------------------

highlight_code :: proc(b: ^strings.Builder, language: string, code: string) {
	config, ok := get_lang_config(language)
	if !ok {
		write_html_escaped(b, code)
		return
	}

	s := scanner_make(code)

	flush_plain :: proc(b: ^strings.Builder, s: ^Text_Scanner) {
		text := scanner_flush_text(s)
		if len(text) > 0 {
			write_html_escaped(b, text)
		}
	}

	for !scanner_at_end(&s) {
		ch, _ := scanner_peek(&s)

		// 1. Block comments
		if len(config.block_comment_open) > 0 && scanner_check_prefix(&s, config.block_comment_open) {
			flush_plain(b, &s)
			scanner_advance(&s, len(config.block_comment_open))
			for !scanner_at_end(&s) {
				if scanner_match_prefix(&s, config.block_comment_close) {
					break
				}
				scanner_advance(&s)
			}
			write_token(b, "cmt", scanner_flush_text(&s))
			continue
		}

		// 2. Line comments
		if len(config.line_comment) > 0 && scanner_check_prefix(&s, config.line_comment) {
			flush_plain(b, &s)
			is_not_newline :: proc(c: byte) -> bool { return c != '\n' }
			scanner_capture_while(&s, is_not_newline)
			write_token(b, "cmt", scanner_flush_text(&s))
			continue
		}

		// 3. Triple-quoted strings (Python)
		if config.has_triple_strings && (scanner_check_prefix(&s, `"""`) || scanner_check_prefix(&s, `'''`)) {
			flush_plain(b, &s)
			quote := s.src[s.pos:][:3]
			scanner_advance(&s, 3)
			for !scanner_at_end(&s) {
				if scanner_match_byte(&s, '\\') {
					scanner_advance(&s)
					continue
				}
				if scanner_check_prefix(&s, quote) {
					scanner_advance(&s, 3)
					break
				}
				scanner_advance(&s)
			}
			write_token(b, "str", scanner_flush_text(&s))
			continue
		}

		// 4. Preprocessor lines (C/C++)
		if config.has_preprocessor && ch == '#' && is_at_line_start(s.src, s.pos) {
			flush_plain(b, &s)
			for !scanner_at_end(&s) {
				if scanner_check_prefix(&s, "\\\n") {
					scanner_advance(&s, 2)
					continue
				}
				next, has_next := scanner_peek(&s)
				if has_next && next == '\n' {
					break
				}
				scanner_advance(&s)
			}
			write_token(b, "pp", scanner_flush_text(&s))
			continue
		}

		// 5. Strings
		if ch == '"' || (ch == '\'' && config.has_single_quote_strings) || (ch == '`' && (config.has_backtick_strings || config.has_raw_strings)) {
			flush_plain(b, &s)
			quote := ch
			scanner_advance(&s)
			if config.has_raw_strings && quote == '`' {
				for !scanner_at_end(&s) {
					if scanner_match_byte(&s, '`') {break}
					scanner_advance(&s)
				}
			} else {
				for !scanner_at_end(&s) {
					c2, _ := scanner_peek(&s)
					if c2 == quote || c2 == '\n' {break}
					if c2 == '\\' {
						scanner_advance(&s)
					}
					scanner_advance(&s)
				}
				scanner_match_byte(&s, quote)
			}
			write_token(b, "str", scanner_flush_text(&s))
			continue
		}

		// 6. Identifiers → keyword / function call check
		if is_ident_start(ch) {
			flush_plain(b, &s)
			word := scanner_capture_while(&s, is_ident_byte)
			if is_keyword(config, word) {
				write_token(b, "kw", word)
			} else {
				next, has_next := scanner_peek(&s)
				if has_next && next == '(' {
					write_token(b, "fn", word)
				} else {
					write_html_escaped(b, word)
				}
			}
			scanner_reset_mark(&s)
			continue
		}

		// 7. Numbers
		is_num_start := ch >= '0' && ch <= '9'
		if !is_num_start && ch == '.' {
			next, has_next := scanner_peek(&s, 1)
			is_num_start = has_next && next >= '0' && next <= '9'
		}
		if is_num_start {
			flush_plain(b, &s)
			scan_number(&s)
			write_token(b, "num", scanner_flush_text(&s))
			continue
		}

		// 8. Everything else
		scanner_advance(&s)
	}

	flush_plain(b, &s)
}

// ---- small utility procs --------------------------------------------------

is_ident_start :: proc(c: byte) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

is_at_line_start :: proc(code: string, pos: int) -> bool {
	if pos == 0 {
		return true
	}
	j := pos - 1
	for j >= 0 {
		if code[j] == '\n' {
			return true
		}
		if code[j] != ' ' && code[j] != '\t' {
			return false
		}
		j -= 1
	}
	return true
}
