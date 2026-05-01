#!/usr/bin/awk -f
#
# Processor for teg files in awk
# https://codeberg.org/9vlc/teg
#
# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2025 2026 Alexey Laurentsyeu
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met
#
# 1. Redistributions of source code must retain the above copyright
# 	notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
# 	notice, this list of conditions and the following disclaimer in the
# 	documentation and/or other materials provided with the distribution.
# 3. Neither the name of the copyright holder nor the names of its
# 	contributors may be used to endorse or promote products derived from
# 	this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
# TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#
# Initialize all global variables
#
function TEG_init() {
	#
	# Internal variables
	#
	
	# Check
	TEG_init_done = 1
	# Did we reach any data in the file
	TEG_reached_data = 0
	# Did we reach the !start call
	TEG_reached_start = 0
	# Blockquote nesting level
	TEG_blockquote_lvl[0] = 0
	# Previous blockquote nesting level
	TEG_blockquote_lvl[1] = 0
	# List nesting level
	TEG_list_lvl[0] = 0
	# Previous list nesting level
	TEG_list_lvl[1] = 0
	# List type
	TEG_list_type[0] = 0
	# List stack
	TEG_list_stack[0] = 0
	# Current heredoc variable delimiter
	TEG_var_long = ""
	# List of HTML element with assigned IDs
	TEG_id_list[""] = 0


	# REGEX for different things
	TEG_reglist["call_inline"] = "\\{![^{][^!]*!\\}"
	TEG_reglist["var_inline"] = "\\{\\$[^{][^$]*\\$\\}"
	TEG_reglist["md_bold"] = "\\*\\*[^*]+\\*\\*"
	TEG_reglist["md_italic"] = "\\*[^*]+\\*"
	TEG_reglist["md_underscore"] = "__[^_]+__"
	TEG_reglist["md_strikethrough"] = "~~[^~]+~~"
	TEG_reglist["md_code"] = "`[^`]+`"
	TEG_reglist["md_link"] = "\\[[^\\]]*\\]\\([^)]*[^\\\\]\\)"
	TEG_reglist["md_spoiler"] = "\\|\\|\\[[^\\]]*\\][^\\|]*\\|\\|"

	# Whitelist for variables that are allowed before !start
	TEG_before_start_list = "(start|abort|var|inc|log|exec_inc)"

	#
	# User accessible vars
	#

	# If we're running teg standalone
	if (!TEG_AS_LIBRARY)
		if (ARGC <= 1)
			TEG_c_vars["file"] = "stdin"
		else
			TEG_c_vars["file"] = ARGV[1]

	# Print a bunch of debugging information
	TEG_c_vars["debug"] = 0
	# Exit on error!
	TEG_c_vars["exit_on_error"] = 1

	# HTML escapes
	TEG_c_vars["escape"] = 1
	# Stop putting <br> after two newlines, value decrements each line until 0
	TEG_c_vars["no_br"] = 0
	# Stop the teg processing for N lines, value decrements each line until 0
	TEG_c_vars["no_proc"] = 0

	TEG_c_vars["title"] = TEG_c_vars["file"]
	TEG_c_vars["description"] = 0
	TEG_c_vars["lang"] = "en-US"
	TEG_c_vars["icon"] = 0
	TEG_c_vars["style"] = 0
	TEG_c_vars["style_inline"] = 0
	TEG_c_vars["script"] = 0
	TEG_c_vars["script_inline"] = 0

	# Current unprocessed line
	TEG_c_vars["curr_line"] = ""
	# Previous processed line
	TEG_c_vars["prev_line"] = "<h"

	# Current element nesting level
	TEG_c_vars["e_nest_lvl"] = 0
	# Are we inside a <pre>?
	TEG_c_vars["inside_pre"] = 0
	# Are we inside a codeblock?
	TEG_c_vars["inside_codeblock"] = 0

	# Color accent (hex) for mobile chromium and some social media embeds
	TEG_c_vars["color_chrome"] = 0
	# URL of an image to embed for social media
	TEG_c_vars["embed_img"] = 0
	# Whether to use OpenGraph for embeds
	TEG_c_vars["embed_og"] = 0
	# Whether to use the twitter protocol for embeds
	TEG_c_vars["embed_twt"] = 0

	# HTTP status (required for cgi)
	TEG_c_vars["status"] = 0
	# HTTP content type (required for cgi)
	TEG_c_vars["ctype"] = "text/html"
	# Color accent for mobile chromium and some social media embeds
	TEG_c_vars["color_chrome"] = 0

}

#
# Check if the string is empty / whitespace
# Return 1 if it is
#
function TEG_is_null(str) {
	gsub(/[ \n\t]/, "", str)
	if (length(str))
		return 0
	else
		return 1
}

#
# Return a string with stripped leading and trailing whitespace
#
function TEG_strip_sp(str) {
	gsub(/^[ \t]+/, "", str)
	gsub(/[ \t]+$/, "", str)
	return str
}

#
# Return a formatted array for debugging
#
function TEG_explode_arr(arr,   str,elem) {
	str = "\t"
	for (elem in arr) {
		elem = elem " : \"" arr[elem] "\""
		str = (str == "\t" ? "\t" elem : str "\n\t" elem)
	}
	str = str "\n"
	return str
}

#
# Split a string containing surround separated substrings into a 1-indexed
#   array with odd entries being text outside of surround separators and
#   even entries inside of surround separators.
#
# Returns the count of entries in the resulting array
#
# Arguments are as follows:
#   Array to write data to
#   Input string
#   REGEX matching a pair of text surrounds
#   Length of one side of a surround
#
# Example:
#   TEG_split_surround(p, "hello %test% world! %aaa%", "%[^%]+%", 1)
# Will write the following to p[]:
#   p[1] = "hello "
#   p[2] = "test"
#   p[3] = " world! "
#   p[4] = "aaa"
#   p[5] = ""
# and return 2
#
function TEG_split_surround(p, str, sep, slen,   i) {
	delete p
	i = 1
	while (match(str, sep)) {
		p[i*2-1] = substr(str, 1, RSTART - 1)
		p[i*2] = substr(str, RSTART + slen, RLENGTH - slen * 2)
		p[i*2+1] = substr(str, RSTART + RLENGTH)

		str = p[i*2+1]
		i ++
	}
	return i - 1
}

#
# Does this file exist?
# Return 1 if so
#
function TEG_exists(file,   r) {
	if (TEG_is_null(file))
		return 0
	r = getline _ < file
	close(file)
	return (r > -1 ? 1 : 0)
}

#
# Complete input path with currently running teg script's path and return a
#   correct relative path to the file for later use.
# If input is a full path, return it as it is,
#
function TEG_relpath(path,   dir) {
	if (match(path, /^\//) || TEG_c_vars["file"] == "stdin")
		return path
	dir = TEG_c_vars["file"]
    sub(/[^\/]*$/, "", dir)
	return dir path
}

#
# Logs various messages to stderr
# Types:
# 1 - debug
# 2 - warning
# 3 - error
#
function TEG_logt(str, type) {
	if (type == 1 || !type) {
		if (TEG_c_vars["debug"])
			print "debug: " str > "/dev/stderr"
		else
			return 1
	} else if (type == 2) {
		print "warning: " str > "/dev/stderr"
	} else if (type == 3) {
		print "error: " str > "/dev/stderr"
		if (TEG_c_vars["exit_on_error"])
			exit TEG_c_vars["exit_on_error"]
	}
	return 0
}

#
# TEG_logt wrapper for debugging where did an error occur
#
function TEG_MARK(optional_str) {
	TEG_c_vars["marker_num"] = (TEG_c_vars["marker_num"] ? TEG_c_vars["marker_num"] : 1)
	TEG_logt("MARKER " TEG_c_vars["marker_num"] (optional_str ? " / " optional_str : ""))
	TEG_c_vars["marker_num"] ++
	return
}

#
# Escape & < > " ' in text
#
function TEG_escape_html(str) {
	gsub(/&/, "\\&amp;", str)
	# Addition: let's not escape ' and " for now
	# gsub(/"/, "\\&quot;", str)
	# gsub(/'/, "\\&apos;", str)
	gsub(/</, "\\&lt;", str)
	gsub(/\\\\/, "\\&#92;", str)
	if (str !~ /^>+( |$)/)
		gsub(/>/, "\\&gt;", str)
	return str
}

#
# Same as before but skip inline calls and some other things that tend to break
#
function TEG_escape_html_wrap(str,   parts,ret,i) {
	if (TEG_c_vars["no_proc"])
		return str
	if (str ~ TEG_reglist["call_inline"]) {
		ret = TEG_split_surround(parts, str, TEG_reglist["call_inline"], 2)
		str = ""
		for (i = 1; i <= ret*2+1; i++) {
			if (i % 2)
				str = str TEG_escape_html(parts[i])
			else
				str = str "{!" parts[i] "!}"
		}
	} else if (str !~ /^![A-Za-z0-9_]+[ \t]/)
		return TEG_escape_html(str)
	return str
}

#
# Replace a surround with an HTML tag
#
# Arguments are as follows:
#   Input string
#   Replacement html tag name
#   Length of one side of a surround
#   HTML escape sequence replacing a surround symbol
#
function TEG_md_resurround(str, elem, regexp, flen, alt,   parts,ralt,ret,i,k) {
	ret = TEG_split_surround(parts, str, regexp, flen)
	if (ret) {
		str = ""
		for (i = 1; i <= ret*2+1; i++)
			if (i % 2)
				str = str parts[i]
			else {
				if (substr(parts[i-1], length(parts[i-1]), 1) == "\\") {
					ralt = ""
					for (k = 1; k <= flen; k++)
						ralt = ralt alt
					str = substr(str, 1, length(str) - 1)
					str = str ralt parts[i] ralt
				} else
					str = str "<"elem">" parts[i] "</"elem">"
			}
	}
	return str
}

#
# Read and concatenate a delimiter-separated list of files into a single variable
#
function TEG_read_list(list, delim,   file,files,cnt,line,r) {
	r = ""
	cnt = split(list, files, delim)
	for (i = 1; i <= cnt; i++) {
		file = TEG_relpath(TEG_strip_sp(files[i]))
		if (!TEG_exists(file)) {
			TEG_logt("file '"file"' does not exist", 2)
			continue
		}

		while ((getline line < file))
			r = r (r == "" ? "" : "\n") line
		close(file)
	}
	return r
}

#
# Markdown processor
# Call for each line and finish execution with one empty string and TEG_c_vars["no_br"] = 1
#
function TEG_md_fmt(str,   indent_len,blockstr,i,start,liststr,ix,rl,link_md,is_image,text,link,end,spoiler_md,preview) {
	if (TEG_c_vars["no_proc"]) {
		return str
	}

	match(str, /^[ \t]*/)
	indent_len = RLENGTH

	#
	# Codeblocks
	#
	if (TEG_c_vars["inside_codeblock"]) {
		if (TEG_c_vars["inside_codeblock"] == 2) {
			TEG_c_vars["inside_codeblock"] = 1
			TEG_c_vars["inside_pre"] = 1
			return "<pre class=\"cb-pre\"><code class=\"cb-code\">" str
		} else if (str == "```") {
			TEG_c_vars["inside_codeblock"] = 0
			TEG_c_vars["inside_pre"] = 0
			return "</code></pre>"
		}
		return str
	} else if (str == "```") {
		# Initialize the codeblock on the next line
		TEG_c_vars["inside_codeblock"] = 2
		return
	}

	#
	# Bold, italic, underscode, strikethrough, code
	#
	str = TEG_md_resurround(str, "strong", TEG_reglist["md_bold"], 2, "&#42;")
	str = TEG_md_resurround(str, "em", TEG_reglist["md_italic"], 1, "&#42;")
	str = TEG_md_resurround(str, "u", TEG_reglist["md_underscore"], 2, "&#95;")
	str = TEG_md_resurround(str, "s", TEG_reglist["md_strikethrough"], 2, "&#126;")
	str = TEG_md_resurround(str, "code", TEG_reglist["md_code"], 1, "&#96;")

	#
	# Headings
	#
	if (str ~ /^# /)
		str = "<h1>" substr(str, 3) "</h1>"
	if (str ~ /^## /)
		str = "<h2>" substr(str, 4) "</h2>"
	if (str ~ /^### /)
		str = "<h3>" substr(str, 5) "</h3>"
	if (str ~ /^#### /)
		str = "<h4>" substr(str, 6) "</h4>"
	if (str ~ /^##### /)
		str = "<h5>" substr(str, 7) "</h5>"
	if (str ~ /^###### /)
		str = "<h6>" substr(str, 8) "</h6>"

	#
	# Horizontal rule
	#
	if (str ~ /^---+$/) {
		str = "<hr>"
	}

	#
	# Blockquotes
	#
	# Current depth
	#
	TEG_blockquote_lvl[0] = 0
	if (str ~ /^>+/) {
		match(str, /^>+/)
		TEG_blockquote_lvl[0] = RLENGTH
		if (TEG_blockquote_lvl[0] > 0)
			str = substr(str, TEG_blockquote_lvl[0] + 2)
	}
	#
	# Depth increases
	#
	blockstr = ""
	if (TEG_blockquote_lvl[0] > TEG_blockquote_lvl[1]) {
		for (i = 0; i < TEG_blockquote_lvl[0] - TEG_blockquote_lvl[1]; i++)
			blockstr = blockstr "<blockquote>"
		blockstr = blockstr "<p>"
	}
	#
	# Depth decreases
	#
	if (TEG_blockquote_lvl[0] < TEG_blockquote_lvl[1]) {
		blockstr = "</p>"
		for (i = 0; i < TEG_blockquote_lvl[1] - TEG_blockquote_lvl[0]; i++)
		blockstr = blockstr "</blockquote>"
	}
	#
	# Depth stays the same
	#
	if (str ~ /^$/ && TEG_blockquote_lvl[0] > 0)
		str = "<br class=\"nl-bq\">"
	if (!TEG_is_null(blockstr))
		str = blockstr str
		TEG_blockquote_lvl[1] = TEG_blockquote_lvl[0]
	#
	# Blockquotes end
	#

	#
	# Lists (help please this is awful)
	#
	TEG_list_type[0] = 0
	TEG_list_lvl[0] = 0

	if (match(str, /^[ \t]*- /))
		TEG_list_type[0] = 1
	else if (match(str, /^[ \t]*[0-9]+\. /))
		TEG_list_type[0] = 2

	if (str ~ /^[ \t]*(-|[0-9]+\.) /) {
		start = substr(str, 1, indent_len)
		gsub(/\t/, "  ", start)
		TEG_list_lvl[0] = length(start) / 2 + 1
		str = substr(str, RLENGTH + 1)
	}

	liststr = ""

	# List start
	if (TEG_list_type[0] && !TEG_list_type[1]) {
		TEG_list_stack[TEG_list_lvl[0]] = TEG_list_type[0]
		liststr = (TEG_list_type[0] == 1 ? "<ul>" : "<ol>")
		str = "<li>" str "</li>"
	}
	# List end
	else if (!TEG_list_type[0] && TEG_list_type[1]) {
		# Close everything
		for (i = TEG_list_lvl[1]; i >= 1; i--) {
			liststr = liststr (TEG_list_stack[i] == 1 ? "</ul>" : "</ol>")
			delete TEG_list_stack[i]
		}
	}
	#
	else if (TEG_list_type[0] && TEG_list_type[1]) {
		# nest++
		if (TEG_list_lvl[0] > TEG_list_lvl[1]) {
			TEG_list_stack[TEG_list_lvl[0]] = TEG_list_type[0]
			liststr = (TEG_list_type[0] == 1 ? "<ul>" : "<ol>")
			str = "<li>" str "</li>"
		}
		# nest--
		else if (TEG_list_lvl[0] < TEG_list_lvl[1]) {
			# Closing up old lists
			for (i = TEG_list_lvl[1]; i > TEG_list_lvl[0]; i--) {
				liststr = liststr (TEG_list_stack[i] == 1 ? "</ul>" : "</ol>")
				delete TEG_list_stack[i]
			}
			# no
			if (TEG_list_type[0] != TEG_list_stack[TEG_list_lvl[0]]) {
				liststr = liststr (TEG_list_stack[TEG_list_lvl[0]] == 1 ? "</ul>" : "</ol>")
				liststr = liststr (TEG_list_type[0] == 1 ? "<ul>" : "<ol>")
				TEG_list_stack[TEG_list_lvl[0]] = TEG_list_type[0]
			}
			str = "<li>" str "</li>"
		}
		else {
			# List type change
			if (TEG_list_type[0] != TEG_list_stack[TEG_list_lvl[0]]) {
				liststr = (TEG_list_stack[TEG_list_lvl[0]] == 1 ? "</ul>" : "</ol>")
				liststr = liststr (TEG_list_type[0] == 1 ? "<ul>" : "<ol>")
				TEG_list_stack[TEG_list_lvl[0]] = TEG_list_type[0]
			}
			str = "<li>" str "</li>"
		}
	}

	if (liststr)
		str = liststr str

	TEG_list_type[1] = TEG_list_type[0]
	TEG_list_lvl[1] = TEG_list_lvl[0]
	#
	# Lists end
	#

	#
	# Add br if there's two consecutive \n
	# (with soooome exclusions)
	#
	if (TEG_is_null(str) && TEG_c_vars["prev_line"] !~ /<\/?(h|ul|ol|pre|p|det)/ && !TEG_c_vars["no_br"]) {
		str = "<br class=\"nl\">"
	}
	if (TEG_c_vars["no_br"] > 0)
		TEG_c_vars["no_br"] --

	#
	# Links and images
	#
	while (ix = match(str, TEG_reglist["md_link"])) {
		is_image = 0
		rl = RLENGTH
		link_md = substr(str, ix, rl)

		if (substr(str, ix - 1, 1) == "!")
			is_image = 1

		text = substr(link_md, 2, index(link_md, "]") - 2)
		link = substr(link_md, length(text) + 4, rl - length(text) - 4)
		gsub(/\\\)/, ")", link)

		start = substr(str, 1, ix - 1)
		end = substr(str, ix + rl)

		if (is_image)
			str = substr(start, 1, length(start) - 1) "<img" (text ? " alt=\""text"\"" : "") " src=\""link"\">" end
		else
			str = start "<a href=\""link"\">"text"</a>" end
	}

	#
	# Spoilers
	# Note: formed like ||[preview text]text inside spoiler||
	#
	while (ix = match(str, TEG_reglist["md_spoiler"])) {
		rl = RLENGTH
		spoiler_md = substr(str, ix, rl)

		preview = substr(spoiler_md, 4, index(spoiler_md, "]") - 4)
		text = substr(spoiler_md, length(preview) + 5, rl - length(preview) - 6)

		start = substr(str, 1, ix - 1)
		end = substr(str, ix + rl)

		str = start "<details><summary>" preview "</summary>" text "</details>" end
	}

	TEG_c_vars["prev_line"] = str
	return str
}

#
# !e element class options
#
# Place an element (HTML tag)
# Stores a list of elements in a global variable and closes them after calling
# for the same element type w/ no props.
#
# The shot argument determines whether to act as !e, !eo or !eoc
#
function TEG_calls_e(call, shot,   elem_name,elem_class,elem_props,arg_count,id,i) {
	elem_name = call[1]
	elem_class = (call[2] ? call[2] : "_")
	arg_count = 0
	for (elem_props in call)
		arg_count ++

	elem_props = ""
	for (i = 3; i <= arg_count; i++) {
		elem_props = elem_props (i > 3 ? " " : "") call[i]
	}
	sub(/^[ \t]+/, "", elem_props)

	elem_name = TEG_strip_sp(elem_name)
	elem_class = TEG_strip_sp(elem_class)
	elem_props = TEG_strip_sp(elem_props)

	if (TEG_is_null(elem_name))
		TEG_logt("empty element", 3)

	# Check if it's an id instead of a class
	id = 0
	if (elem_class ~ /^#/) {
		id = 1
		elem_class = substr(elem_class, 2)

		if (TEG_id_list[elem_class] == 1)
			TEG_logt("element id '" elem_class "' already taken", 3)
	}

	if (shot == 0) {
		if (!TEG_elems[elem_name "_" elem_class]) {
			TEG_logt("new element: '" elem_name "'")
			TEG_elems[elem_name "_" elem_class] = 1
			TEG_c_vars["e_nest_lvl"] ++
			return sprintf("<%s%s%s>\n",
				elem_name,
				(elem_class == "_" ? "" : (id ? " id" : " class")"=\"" elem_class "\""),
				(elem_props  ? " " elem_props : ""))
		} else {
			TEG_logt("closing element: '" elem_name "'")
			TEG_elems[elem_name "_" elem_class] = 0
			if (id)
				TEG_id_list[elem_class] = 1
			TEG_c_vars["e_nest_lvl"] --
			return "</" elem_name ">"
		}
	} else if (shot == 1) {
		TEG_logt("new oneshot (open) element: '" elem_name "'")
		if (id)
			TEG_id_list[elem_class] = 1
		return sprintf("<%s%s%s>",
			elem_name,
			(elem_class == "_" ? "" : (id ? " id" : " class")"=\"" elem_class "\""),
			(elem_props  ? " " elem_props : ""))
	} else if (shot == 2) {
		TEG_logt("new oneshot (closed) element: '" elem_name "'")
		if (id)
			TEG_id_list[elem_class] = 1
		return sprintf("<%s%s%s></%s>",
			elem_name,
			(elem_class == "_" ? "" : (id ? " id" : " class")"=\"" elem_class "\""),
			(elem_props  ? " " elem_props : ""),
			elem_name)
	}
}

#
# !start
#
# Start the page
# Creates doctype, head, opens body.
#
function TEG_calls_start(call,   str,line,cnt,a,i) {
	str = ""

	if (TEG_reached_start)
		return

	if (TEG_c_vars["status"]) {
		str = str "Status: " TEG_c_vars["status"]
		if (!TEG_is_null(TEG_c_vars["ctype"]))
			str = str"\n" "Content-type: " TEG_c_vars["ctype"]
		else
			str = str"\n" "Content-type: text/html"
		str = str"\n" "\n"
	}

	str = str     "<!DOCTYPE html>"
	str = str"\n" "<!-- https://codeberg.org/9vlc/teg -->"
	str = str"\n" "<html lang=\"" TEG_c_vars["lang"] "\">"
	str = str"\n" "<head>"
	str = str"\n" "\t<meta charset=\"UTF-8\">"
	str = str"\n" "\t<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
	if (TEG_c_vars["embed_og"])
		str = str"\n" "\t<meta property=\"og:type\" content=\"website\">"

	if (TEG_c_vars["title"]) {
		str = str"\n" "\t<title>" TEG_c_vars["title"] "</title>"
		if (TEG_c_vars["embed_og"])
			str = str"\n" "\t<meta property=\"og:title\" content=\"" TEG_c_vars["title"] "\">"
		if (TEG_c_vars["embed_twt"])
			str = str"\n" "\t<meta name=\"twitter:title\" content=\"" TEG_c_vars["title"] "\">"
	}

	if (TEG_c_vars["description"]) {
		str = str"\n" "\t<meta name=\"description\" content=\"" TEG_c_vars["description"] "\">"
		if (TEG_c_vars["embed_og"])
			str = str"\n" "\t<meta property=\"og:description\" content=\"" TEG_c_vars["description"] "\">"
		if (TEG_c_vars["embed_twt"])
			str = str"\n" "\t<meta name=\"twitter:description\" content=\"" TEG_c_vars["description"] "\">"
	}

	if (TEG_c_vars["embed_img"]) {
		if (TEG_c_vars["embed_og"])
			str = str"\n" "\t<meta property=\"og:image\" content=\"" TEG_c_vars["embed_img"] "\">"
		if (TEG_c_vars["embed_twt"]) {
			str = str"\n" "\t<meta name=\"twitter:card\" content=\"summary_large_image\">"
			str = str"\n" "\t<meta name=\"twitter:image\" content=\"" TEG_c_vars["embed_img"] "\">"
		}
	}

	if (TEG_c_vars["color_chrome"])
		str = str"\n" "\t<meta name=\"theme-color\" content=\"" TEG_c_vars["color_chrome"] "\">"

	if (TEG_c_vars["icon"])
		str = str"\n" "\t<link rel=\"icon\" href=\"" TEG_c_vars["icon"] "\">"

	if (TEG_c_vars["style"]) {
		cnt = split(TEG_c_vars["style"], a, ";")
		for (i = 1; i <= cnt; i++)
			str = str"\n" "\t<link rel=\"stylesheet\" type=\"text/css\" href=\"" TEG_strip_sp(a[i]) "\">"
	}

	if (TEG_c_vars["style_inline"]) {
		TEG_logt("starting inline style")
		str = str"\n" "\t<style>" TEG_read_list(TEG_c_vars["style_inline"], ";")
		str = str"\n" "\t</style>"
	}

	if (TEG_c_vars["script"]) {
		cnt = split(TEG_c_vars["script"], a, ";")
		for (i = 1; i <= cnt; i++)
			str = str"\n" "\t<script src=\"" TEG_strip_sp(a[i]) "\"></script>"
	}

	TEG_reached_start = 1
	TEG_c_vars["no_proc"] ++
	str = str"\n" "</head>"
	str = str"\n" "<body>"

	#
	# Inline scripts must be in body (I believe so)
	#
	if (TEG_c_vars["script_inline"]) {
		TEG_logt("starting inline script")
		str = str"\n" "\t<script>" TEG_read_list(TEG_c_vars["script_inline"], ";")
		str = str"\n" "\t</script>"
	}
	return str
}

#
# !abort exitcode
#
# Abort execution of a teg script
# No return
#
function TEG_calls_abort(call) {
	if (!TEG_reached_start) {
		if (TEG_c_vars["status"]) {
			str = str     "Status: " TEG_c_vars["status"]
			if (!TEG_is_null(TEG_c_vars["ctype"]))
				str = str"\n" "Content-type: " TEG_c_vars["ctype"]
			else
				str = str"\n" "Content-type: text/html"
			str = str"\n" "\n"
		}
	} else {
		# awk's END runs on exit, so don't know what to put here for now
	}

	printf("%s", str)
	exit((call[0] ? call[0] : 1))
}

#
# !exec_raw command ...
#
# Execute a command and return its output
#
function TEG_calls_exec_raw(call,   str,line) {
	str = ""
	if (TEG_is_null(call[0])) {
		TEG_logt("empty !exec_raw command", 3)
		return
	}

	while((call[0] | getline line) > 0)
		str = (str ? str "\n" : "") line
	close(call[0])

	return str
}

#
# !exec_fmt command ...
#
# Same as before, just place the output in a codeblock
#
function TEG_calls_exec_fmt(call,   str,line,tmp,i,c) {
	c = 0
	str = ""
	if (TEG_is_null(call[0])) {
		TEG_logt("empty !exec_fmt command", 3)
		return
	}

	#
	# Copying the exec_inc approach here "just in case"
	#
	while((call[0] | getline line) > 0) {
		tmp[c] = line
		c ++
	}
	close(call[0])

	for (i = 0; i < c; i++)
		str = str TEG_escape_html(tmp[i]) "\n"

	TEG_c_vars["no_proc"] ++
	return "<pre class=\"cb-pre\"><code class=\"cb-code\">" str "</code></pre>"
}

#
# !exec_inc command ...
#
# Execute a command and include (TEG_proc) its output
#
function TEG_calls_exec_inc(call,   str,line,tmp,i,c) {
	c = 0
	str = ""
	if (TEG_is_null(call[0])) {
		TEG_logt("empty !exec_raw command", 3)
		return
	}

	#
	# Must separate getline and TEG_proc else we get a nasty
	# vulnerability on gawk because of pipe propagation
	# (I should probably report this someday???)
	#
	while((call[0] | getline line) > 0) {
		tmp[c] = line
		c ++
	}
	close(call[0])

	for (i = 0; i < c; i++)
		str = str TEG_proc(tmp[i])

	TEG_c_vars["no_proc"] ++
	return str
}

#
# !var variable=value
#
# Set variable to value.
# If value is not provided
#
function TEG_calls_var(call,   eqpos,key,value,marker) {
	eqpos = index(call[0], "=")

	if (!eqpos) {
		eqpos = index(call[0], "<")
		if (!eqpos)
			return TEG_c_vars[key]

		# < logic
		key = substr(call[0], 1, eqpos - 1)
		marker = substr(call[0], eqpos + 1)

		# Can only have up to one at the same time, sorry
		if (TEG_var_long)
			TEG_logt("can't do two long variables", 3)
		else {
			TEG_var_long = key"<"marker
			TEG_logt("long var: '"TEG_var_long"'")
		}
		TEG_c_vars["no_br"] ++
		return
	}

	# = logic
	key = substr(call[0], 1, eqpos - 1)
	value = substr(call[0], eqpos + 1)

	if (value ~ /^-?[0-9]+$/)
		TEG_c_vars[key] = value + 0
	else
		TEG_c_vars[key] = value

	TEG_logt("'"key"' = ""'"value"'")
	TEG_c_vars["no_br"] ++
	return
}

#
# !inc file
#
# Include a file
# This was the most difficult call to implement
#
function TEG_calls_inc(call,   inc_file,line,prev_file,str) {
	TEG_logt("including '" call[0] "'")
	inc_file = TEG_relpath(call[0])

	if (!TEG_exists(inc_file)) {
		TEG_logt("teg file '" inc_file "' does not exist", 3)
		return
	}

	str = ""
	TEG_c_vars["no_br"] ++
	prev_file = TEG_c_vars["file"]
	TEG_c_vars["file"] = inc_file

	while ((getline line < inc_file) > 0) {
		str = str TEG_proc(line)
	}
	close(inc_file)

	TEG_c_vars["file"] = prev_file
	TEG_c_vars["no_proc"] ++
	return str
}

#
# !log text
#
# Prints text to stderr
#
function TEG_calls_log(call) {
	print call[0] > "/dev/stderr"
	TEG_c_vars["no_br"] ++
	return
}

#
# Run a call
# 
# explicit = 1 - Process the call even before !start
# 
# call["name"] - call name
# call[0]      - concat args
# call[1+]     - args
#
function TEG_callproc(str, explicit,   len,call,long_key,long_marker,delim,nope,i) {
	if (TEG_c_vars["no_proc"])
		return str

	# Still process even if no_proc or inside_codeblock are set
	explicit = (explicit ? 1 : 0)

	if (TEG_var_long) {
		delim = index(TEG_var_long, "<")
		long_key = substr(TEG_var_long, 1, delim - 1)
		long_marker = substr(TEG_var_long, delim + 1)
	}

	nope = 0
	if (str ~ /^![^\[]/)
		len = split(substr(str, 2), call, " ")
	else if (explicit)
		len = split(str, call, " ")
	else if (TEG_var_long)
		nope = 1
	else
		return str

	if (!nope) {
		call["name"] = call[1]
		for (i = 2; i <= len; i++) {
			call[i - 1] = call[i]
			call[0] = call[0] (i > 2 ? " " : "") call[i]
		}
		call[len] = ""

		# Do not run if...
		if (!explicit && (TEG_c_vars["no_proc"] || TEG_c_vars["inside_codeblock"]))
			return str
		else if (!explicit && !TEG_reached_start && !TEG_var_long && call["name"] !~ TEG_before_start_list) {
			TEG_logt("skipping data before start call", 2)
			return
		}

		if (call["name"] == "start")
			str = TEG_calls_start(call)
		else if (call["name"] == "abort")
			str = TEG_calls_abort(call)
		else if (call["name"] == "e")
			str = TEG_calls_e(call, 0)
		else if (call["name"] == "eo")
			str = TEG_calls_e(call, 1)
		else if (call["name"] == "eoc")
			str = TEG_calls_e(call, 2)
		else if (call["name"] == "exec_raw")
			str = TEG_calls_exec_raw(call)
		else if (call["name"] == "exec_fmt")
			str = TEG_calls_exec_fmt(call)
		else if (call["name"] == "exec_inc")
			str = TEG_calls_exec_inc(call)
		else if (call["name"] == "var")
			str = TEG_calls_var(call)
		else if (call["name"] == "inc")
			str = TEG_calls_inc(call)
		else if (call["name"] == "log")
			str = TEG_calls_log(call)
		else
			TEG_logt("unknown call: '" call["name"] "'", 2)
	}

	# If we're doing a !var name<EOL
	if (TEG_var_long && long_marker) {
		if (str == long_marker) {
			TEG_var_long = ""
			TEG_logt("str: "str" marker: "long_marker)
			TEG_c_vars["no_br"] ++ # +2
			TEG_c_vars[long_key] = TEG_c_vars[long_key] TEG_md_fmt("")
		}
		else
			TEG_c_vars[long_key] = TEG_c_vars[long_key] TEG_md_fmt(str) "\n"

		TEG_c_vars["no_br"] ++
		return
	}

	return str
}

#
# Expand inline variables and calls
# Inline variable: {$var_name$}
# Inline call: {!call_name args ...!}
#
function TEG_expand_inline(str,   ret,parts,i) {
	if (TEG_c_vars["no_proc"])
		return str
	#
	# First expand all variables
	#
	if (str ~ TEG_reglist["var_inline"]) {
		ret = TEG_split_surround(parts, str, TEG_reglist["var_inline"], 2)
		str = ""
		for (i = 1; i <= ret*2+1; i++)
			if (i % 2)
				str = str parts[i]
			else if (substr(parts[i-1], length(parts[i-1]), 1) == "\\")
				str = substr(str, 1, length(str) - 1) "&#123;&#36;" parts[i] "&#36;&#125;"
			else
				str = str TEG_c_vars[parts[i]]
	}

	#
	# Then run the calls
	#
	if (str ~ TEG_reglist["call_inline"]) {
		ret = TEG_split_surround(parts, str, TEG_reglist["call_inline"], 2)
		str = ""
		for (i = 1; i <= ret*2+1; i++)
			if (i % 2)
				str = str parts[i]
			else if (substr(parts[i-1], length(parts[i-1]), 1) == "\\")
				str = substr(str, 1, length(str) - 1) "&#123;&#33;" parts[i] "&#33;&#125;"
			else
				str = str TEG_callproc(parts[i], 1)
	}

	return str
}

#
# The main teg processor function
#
function TEG_proc(str) {
	if (!TEG_init_done) {
		TEG_logt("called TEG_proc() without prior TEG_init()", 3)
		exit(1)
	}

	TEG_c_vars["curr_line"] = str

	if (str ~ /^==/ && !TEG_c_vars["inside_codeblock"] && !TEG_c_vars["no_proc"])
		return

	if (!TEG_reached_start && !TEG_var_long) {
		# Pre-start call whitelist
		if (str ~ "^!"TEG_before_start_list) {
			str = TEG_expand_inline(str)
			str = TEG_callproc(str)
		}
		else if (TEG_var_long)
			str = TEG_callproc(str)
		else if (str ~ /^[ \t]*$/)
			return
		else {
			TEG_logt("skipping data before start call", 2)
			return
		}
	}

	if (TEG_c_vars["escape"])
		str = TEG_escape_html_wrap(str)
	str = TEG_expand_inline(str)
	str = TEG_callproc(str)
	if (!TEG_var_long)
		str = TEG_md_fmt(str)

	# New special case for codeblocks (makes html less prettier but idc)
	if (TEG_c_vars["inside_codeblock"])
		str = "\n" str
	else if ((TEG_c_vars["curr_line"] !~ /^![^ \t].+/) && !TEG_var_long)
		str = str "\n"

	if (TEG_c_vars["no_proc"] && TEG_c_vars["no_proc"] ~ /^[0-9]+$/)
		TEG_c_vars["no_proc"] --
	else if (TEG_c_vars["curr_line"] == TEG_c_vars["no_proc"]) {
		TEG_c_vars["no_proc"] = 0
		return
	}

	TEG_c_vars["prev_line"] = str
	return str
}

function TEG_end() {
	if (TEG_reached_start) {
		# Cleanly finish all pending markdown work
		TEG_c_vars["no_br"] ++
		TEG_md_fmt("")
		return "</body></html>"
	}
}

#
# If we're running standalone teg
#
BEGIN {
	if (!TEG_AS_LIBRARY)
		TEG_init()
}

{
	if (!TEG_AS_LIBRARY)
		printf("%s", TEG_proc($0))
}

END {
	if (!TEG_AS_LIBRARY)
		printf("%s\n", TEG_end())
}
