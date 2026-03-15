package main

// ---------------------------------------------------------------------------
// Markdown IR Types
// ---------------------------------------------------------------------------

Document :: struct {
	blocks: [dynamic]Block,
}

Block :: union {
	Heading,
	Paragraph,
	Code_Block,
	List,
	Blockquote,
	Horizontal_Rule,
	Sidenote_Def,
}

Heading :: struct {
	level:   int,
	inlines: [dynamic]Inline,
}

Paragraph :: struct {
	inlines: [dynamic]Inline,
}

Code_Block :: struct {
	language: string,
	code:     string,
}

List :: struct {
	ordered: bool,
	items:   [dynamic][dynamic]Inline,
}

Blockquote :: struct {
	inlines: [dynamic]Inline,
}

Horizontal_Rule :: struct {}

Inline :: union {
	Text,
	Bold,
	Italic,
	Code_Span,
	Link,
	Image,
	Sidenote_Ref,
}

Text :: struct {
	text: string,
}

Bold :: struct {
	children: [dynamic]Inline,
}

Italic :: struct {
	children: [dynamic]Inline,
}

Code_Span :: struct {
	text: string,
}

Link :: struct {
	text: string,
	url:  string,
}

Image :: struct {
	alt: string,
	url: string,
}

Sidenote_Ref :: struct {
	label: string,
}

Sidenote_Def :: struct {
	label:   string,
	inlines: [dynamic]Inline,
}

// ---------------------------------------------------------------------------
// SSG Types
// ---------------------------------------------------------------------------

Frontmatter :: struct {
	title:       string,
	author:      string,
	date:        string,
	modified:    string,
	tags:        [dynamic]string,
	priority:    int,
	description: string,
	toc:         bool,
	draft:       bool,
	series:      string,
	series_part: int,
}

Heading_Info :: struct {
	level: int,
	text:  string,
	id:    string,
}

Content_Item :: struct {
	frontmatter: Frontmatter,
	slug:        string,
	source_path: string,
	body_html:   string,
	headings:    [dynamic]Heading_Info,
}

Article :: Content_Item
Project :: Content_Item

Footer_Link :: struct {
	text: string,
	url:  string,
}

Nav_Item :: struct {
	label: string,
	href:  string,
}

Site_Config :: struct {
	blog_dir:       string,
	content_dir:    string,
	output_dir:     string,
	site_title:     string,
	site_url:       string,
	description:    string,
	avatar:         string,
	accent_color:       string,
	accent_color_light: string,
	footer_tagline: string,
	footer_links:   [dynamic]Footer_Link,
	nav_items:      [dynamic]Nav_Item,
	css:            string,
}
