#!/usr/bin/awk -f
#
# processor for teg files in awk
# https://github.com/9vlc/teg
#
# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2025 Alexey Laurentsyeu
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

BEGIN {
	if (ARGC <= 1)
		c_vars["file"] = "stdin"
	else
		c_vars["file"] = ARGV[1]

	reached_data = 0
	reached_start = 0
	inside_codeblock = 0
	blockquote_lvl[0] = 0
	blockquote_lvl[1] = 0
	list_lvl[0] = 0
	list_lvl[1] = 0
	prev_str = "<h do not change this"

	c_vars["escape"] = 1
	c_vars["title"] = c_vars["file"]
	c_vars["description"] = 0
	c_vars["lang"] = "en-US"
	c_vars["icon"] = 0
	c_vars["style"] = 0
	c_vars["style_inline"] = 0
	c_vars["script"] = 0
	c_vars["script_inline"] = 0
	c_vars["color_chrome"] = 0
	c_vars["debug"] = 1
	c_vars["exit_on_error"] = 1
	c_vars["nobr"] = 0
}

#
# check if the string is empty / whitespace
#
function is_null(str) {
	if (str ~ /^[ \t]*$/)
		return 1
	else
		return 0
}

#
# strip leading and trailing whitespace from a string
#
function strip_sp(str) {
	gsub(/^[ \t]+/, "", str)
	gsub(/[ \t]+$/, "", str)
	return str
}

#
# does this file exist?
#
function exists(file,   r) {
	if (is_null(file))
		return 0
	r = getline _ < file
	close(file)
	return (r > -1 ? 1 : 0)
}

#
# return relative (or not) path of argument path in relation to
# currently worked on file's path
#
function relpath(path,   dir) {
	if (match(path, /^\//) || c_vars["file"] == "stdio")
		return path
	dir = c_vars["file"]
    sub(/[^\/]*$/, "", dir)
	return dir path
}

#
# logs various messages to stderr
# types:
# 1 - debug
# 2 - warning
# 3 - error
#
function logt(txt, type) {
	if (type == 1 || !type) {
		if (c_vars["debug"])
			print "debug: " txt > "/dev/stderr"
		else
			return 1
	} else if (type == 2) {
		print "warning: " txt > "/dev/stderr"
	} else if (type == 3) {
		print "error: " txt > "/dev/stderr"
		if (c_vars["exit_on_error"])
			exit c_vars["exit_on_error"]
	}
	return 0
}

#
# escape symbols like & < > " '
#
function escape_html(str) {
	gsub(/&/, "\\&amp;", str);
	gsub(/"/, "\\&quot;", str);
	gsub(/'/, "\\&apos;", str);
	gsub(/</, "\\&lt;", str);
	if (str !~ /^>+( |$)/)
		gsub(/>/, "\\&gt;", str);
	return str;
}

#
# str - input string
# elem - html element to put match in
# regexp - regex match for a symmetric surround of a word
# flen - length of one of the sides of the surround (DO NOT OMMIT!!!!!!)
#
function md_resurround(str, elem, regexp, flen,   start,mid,end) {
	while (i = match(str, regexp)) {
		start = substr(str, 1, i - 1)
		mid = substr(str, i + flen, RLENGTH - 2 * flen)
		end = substr(str, i + RLENGTH)
		str = start "<"elem">" mid "</"elem">" end
	}
	return str
}

#
# temporary function?
#
function md_resurround_wrap(str) {
	#
	# bold, italic, underscode, strikethrough, etc
	#
	str = md_resurround(str, "strong", "\\*\\*[^*]+\\*\\*", 2)
	str = md_resurround(str, "em", "\\*[^*]+\\*", 1)
	str = md_resurround(str, "u", "__[^_]+__", 2)
	str = md_resurround(str, "s", "~~[^~]+~~", 2)
	str = md_resurround(str, "code", "`[^`]+`", 1)
	return str
}

#
# whatever.
# stores a whole bunch of global variables, call this for each line you
# want to convert from markdown to html
#
function tegmd_fmt(str) {
	match(str, /^[ \t]*/)
	indent_len = RLENGTH

	#
	# codeblocks
	#
	if (inside_codeblock) {
		if (inside_codeblock == 2) {
			inside_codeblock = 1
			return "<pre class=\"cb\"><code class=\"cb\">" str
		} else if (str == "```") {
			inside_codeblock = 0
			return "</code></pre>"
		}
		return str
	} else if (str == "```") {
		inside_codeblock = 2
		return
	}

	str = md_resurround_wrap(str)

	#
	# headings
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
	# horizontal rule
	#
	if (str ~ /^---+$/)
		str = "<hr>"

	#
	# blockquotes
	#
	# current depth
	#
	blockquote_lvl[0] = 0
	if (str ~ /^>+ /) {
		match(str, /^>+/)
		blockquote_lvl[0] = RLENGTH
    	if (blockquote_lvl[0] > 0)
    		str = substr(str, blockquote_lvl[0] + 2)
	}
	#
	# depth increases
	#
	blockstr = ""
	if (blockquote_lvl[0] > blockquote_lvl[1]) {
		for (i = 0; i < blockquote_lvl[0] - blockquote_lvl[1]; i++)
			blockstr = blockstr "<blockquote>"
		blockstr = blockstr "<p>"
	#
	# depth decreases
	#
	} else if (blockquote_lvl[0] < blockquote_lvl[1]) {
		blockstr = "</p>" blockstr
		for (i = 0; i < blockquote_lvl[1] - blockquote_lvl[0]; i++)
			blockstr = "</blockquote>" blockstr
	#
	# depth stays the same
	#
	} else if (str ~ /^$/ && blockquote_lvl[0] > 0)
		 str = "<br class=\"nl-bq\">"
	if (!is_null(blockstr))
		str = blockstr str
	blockquote_lvl[1] = blockquote_lvl[0]
	#
	# blockquotes end
	#

	#
	# lists
	#
	list_type[0] = 0
	if (match(str, /^[ \t]*- /))
		list_type[0] = 1
	else if (match(str, /^[ \t]*[0-9]+\. /))
		list_type[0] = 2

	if (str ~ /^[ \t]*(-|[0-9]+\.) /) {
		list_lvl[0] = indent_len / 2 + 1
		str = substr(str, RLENGTH + 1)
	}

	if (list_type[0] && !list_type[1]) {
		str = (list_type[0] == 1 ? "<ul>" : "<ol>") (str ? "<li>" str "</li>" : "")
	} else if (!list_type[0] && list_type[1]) {
		str = (list_type[1] == 1 ? "</ul>" : "</ol>") str
	} else if (list_type[0] && list_type[1]) {

		if (list_lvl[0] > list_lvl[1])
			str = (list_type[0] == 1 ? "<ul>" : "<ol>") (str ? "<li>" str "</li>" : "")
		else if (list_lvl[0] < list_lvl[1])
			str = (list_type[1] == 1 ? "</ul>" : "</ol>") (str ? "<li>" str "</li>" : "")
		else if (list_type[0] != list_type[1])
			str = (list_type[1] == 1 ? "</ul>" : "</ol>") (list_type[0] == 1 ? "<ul>" : "<ol>") (str ? "<li>" str "</li>" : "")
		else
			str = "<li>" str "</li>"
	}

	list_type[1] = list_type[0]
	list_lvl[1] = list_lvl[0]
	#
	# lists end
	#

	#
	# add br if there's two consecutive \n
	#
	if (str ~ /^$/ && prev_str !~ /(<\/?h[1-6]|<br)/ && c_vars["nobr"] < 1)
		str = "<br class=\"nl\">"

	#
	# links and images
	#
	while (ix = match(str, /\[[^\]]*\]\([^)]*\)/)) {
		is_image = 0
		rl = RLENGTH
		link_md = substr(str, ix, rl)

		if (substr(str, ix - 1, 1) == "!")
			is_image = 1

		text = substr(link_md, 2, index(link_md, "]") - 2)
		link = substr(link_md, length(text) + 4, rl - length(text) - 4)

		start = substr(str, 1, ix - 1)
		end = substr(str, ix + rl)

		if (is_image)
			str = substr(start, 1, length(start) - 1) "<img alt=\""text"\" src=\""link"\">" end
		else
			str = start "<a href=\""link"\">"text"</a>" end
	}

	#
	# spoilers
	# note: formed like ||[preview text]text inside spoiler||
	#
	while (ix = match(str, /\|\|\[[^\]]*\][^\|]*\|\|/)) {
		rl = RLENGTH
		spoiler_md = substr(str, ix, rl)

		preview = substr(spoiler_md, 4, index(spoiler_md, "]") - 4)
		text = substr(spoiler_md, length(preview) + 5, rl - length(preview) - 6)

		start = substr(str, 1, ix - 1)
		end = substr(str, ix + rl)

		str = start "<details><summary>" preview "</summary>" text "</details>" end
	}

	prev_str = str
	return str
}

#
# !e element class options
#
# place an element (html tag)
# stores a list of elements in a global variable and
# closes them when user calls the same element again
#
function calls_e(call,   elem_name,elem_class,elem_props,arg_count) {
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

	elem_name = strip_sp(elem_name)
	elem_class = strip_sp(elem_class)
	elem_props = strip_sp(elem_props)

	if (!elems[elem_name "_" elem_class]) {
		logt("new element: '" elem_name "'")
		elems[elem_name "_" elem_class] = 1
		elem_nest_lvl ++
		return sprintf("<%s%s%s>\n",
			elem_name,
			(elem_class == "_" ? "" : " class=\"" elem_class "\""),
			(elem_props  ? " " elem_props : ""))
	} else {
		logt("closing element: '" elem_name "'")
		elems[elem_name "_" elem_class] = 0
		elem_nest_lvl --
		return "</" elem_name ">"
	}
}

#
# !eo element class options
#
# same as before, just don't remember the state
# meant for self-closing tags
#
function calls_eo(call,   elem_name,elem_class,elem_props,arg_count) {
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

	elem_name = strip_sp(elem_name)
	elem_class = strip_sp(elem_class)
	elem_props = strip_sp(elem_props)

	logt("new oneshot element: '" elem_name "'")
	return sprintf("<%s%s%s>\n",
		elem_name,
		(elem_class == "_" ? "" : " class=\"" elem_class "\""),
		(elem_props  ? " " elem_props : ""))
}

#
# !start
#
# start the page
# creates doctype, head, opens body.
#
function calls_start(call,   str,line) {
	str = ""

	if (reached_start)
		return

	str = str     "<!DOCTYPE html>"
	str = str"\n" "<!-- Generated with teg: https://github.com/9vlc/teg -->"
	str = str"\n" "<html lang=\"" c_vars["lang"] "\">"
	str = str"\n" "<head>"
	str = str"\n" "\t<meta charset=\"UTF-8\">"
	str = str"\n" "\t<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"

	if (c_vars["title"])
		str = str"\n" "\t<title>" c_vars["title"] "</title>"

	if (c_vars["description"])
		str = str"\n" "\t<meta name=\"description\" content=\"" c_vars["description"] "\">"

	if (c_vars["color_chrome"])
		str = str"\n" "\t<meta name=\"theme-color\" content=\"" c_vars["color_chrome"] "\">"

	if (c_vars["icon"])
		str = str"\n" "\t<link rel=\"icon\" href=\"" c_vars["icon"] "\">"

	if (c_vars["style"])
		str = str"\n" "\t<link rel=\"stylesheet\" type=\"text/css\" href=\"" c_vars["style"] "\">"

	if (c_vars["style_inline"]) {
		logt("starting inline style")
		style_file = relpath(c_vars["style_inline"])
		logt("style file: '" style_file "'")

		if (exists(style_file)) {
			str = str"\n" "\t<style>"
			while ((getline line < style_file) > 0)
				str = str"\n" line
			str = str"\n" "\t</style>"
			close(style_file)
		} else
			logt("style file '" style_file "' does not exist", 2)
	}

	if (c_vars["script"])
		str = str"\n" "\t<script src=\"" c_vars["script"] "\">"

	if (c_vars["script_inline"]) {
		logt("starting inline script")
		script_file = relpath(c_vars["script_inline"])
		logt("script script_file: '" script_file "'")

		if (exists(script_file)) {
			str = str"\n" "\t<script>"
			while ((getline line < script_file) > 0)
				str = str"\n" line
			str = str"\n" "\t</script>"
			close(script_file)
		} else
			logt("script file '" relpath(c_vars["script_inline"]) "' does not exist", 3)
	}

	reached_start = 1
	str = str"\n" "</head>"
	str = str"\n" "<body>"
	return str
}

#
# !exec_raw command ...
#
# execute a command and return its output
#
function calls_exec_raw(call,   str,line) {
	str = ""
	if (is_null(call[0])) {
		logt("empty !exec_raw command", 3)
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
# same as before, just place the output in a codeblock
#
function calls_exec_fmt(call,   str,line) {
	str = ""
	if (is_null(call[0])) {
		logt("empty !exec_fmt command", 3)
		return
	}

	while((call[0] | getline line) > 0) {
		str = (str ? str "\n" : "") escape_html(line)
	}
	close(call[0])
	# make the markdown formatter not add a break after code
	prev_str = "<h"

	return "<pre class=\"cb\"><code class=\"cb\">" str "</code></pre>"
}

#
# !var variable=value
#
# set variable to value.
# if value is not provided
#
function calls_var(call,   eqpos,key,value) {
	eqpos = index(call[0], "=")
	if (!eqpos)
		return c_vars[key]

	key = substr(call[0], 1, eqpos - 1)
	value = substr(call[0], eqpos + 1)

	if (value ~ /^-?[0-9]+$/)
		c_vars[key] = value + 0
	else
		c_vars[key] = value

	logt("'"key"' = ""'"value"'")
	return
}

#
# debug
#
function MARK(opt_txt) {
	c_vars["marker_num"] = (c_vars["marker_num"] ? c_vars["marker_num"] : 1)
	logt("MARKER " c_vars["marker_num"] (opt_txt ? " / " opt_txt : ""))
	c_vars["marker_num"] ++
	return
}

#
# !inc file
#
# include a file
# this was the most difficult call to implement
#
function calls_inc(call,   inc_file,line,prev_file,str) {
	logt("including '" call[0] "'")
	inc_file = relpath(call[0])

	if (!exists(inc_file)) {
		logt("teg file '" inc_file "' does not exist", 3)
		return
	}

	str = ""
	prev_str = "<h"
	prev_file = c_vars["file"]
	c_vars["file"] = inc_file

	while ((getline line < inc_file) > 0) {
		str = str tegproc(line)
	}
	close(inc_file)

	c_vars["file"] = prev_file
	return str
}

#
# everything
#
function tegproc(str) {
	if (str ~ /^==/)
		return

	#
	# calls
	#
	if (str ~ /^![^\[]/) {
		#
		# what we got:
		# call[0]  - args, concat
		# call[1+] - args, split
		#

		len = split(substr(str, 2), call, " ")
		call["name"] = call[1]
		for (i = 2; i <= len; i++) {
			call[i - 1] = call[i]
			call[0] = call[0] (i > 2 ? " " : "") call[i]
		}
		call[len] = ""

		if (!reached_start && call["name"] !~ /(inc|var|start)/) {
			logt("skipping data before start call", 2)
			return
		}

		#
		# run the calls
		#
		ret = str # default: the string
		if (call["name"] == "start")
			ret = calls_start(call)
		if (call["name"] == "e")
			ret = calls_e(call)
		if (call["name"] == "eo")
			ret = calls_eo(call)
		if (call["name"] == "exec_raw")
			ret = calls_exec_raw(call)
		if (call["name"] == "exec_fmt")
			ret = calls_exec_fmt(call)
		if (call["name"] == "var")
			ret = calls_var(call)
		if (call["name"] == "inc")
			ret = calls_inc(call)

		return ret
	}

	#
	# skip extra newlines
	#
	if (str !~ /^([ \t]*|![^\[])$/)
		reached_data = 1

	if (!reached_data)
		return

	if (!reached_start) {
		logt("skipping data before start call", 2)
		return
	}

	if (c_vars["escape"])
		str = escape_html(str)

	str = tegmd_fmt(str) "\n"
	return str
}

{
	printf("%s", tegproc($0))
}


END {
	tegproc("") # finish all our markdown things
	if (reached_start) {
		print "</body>"
		print "</html>"
	}
}
