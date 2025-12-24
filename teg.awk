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
	blockquote_lvl[0] = 0
	blockquote_lvl[1] = 0
	list_lvl[0] = 0
	list_lvl[1] = 0
	list_type[0] = 0
	list_stack[0] = 0

	reglist["call_inline"] = "\\{![^{][^!]*!\\}"
	reglist["var_inline"] = "\\{\\$[^{][^$]*\\$\\}"	
	reglist["md_bold"] = "\\*\\*[^*]+\\*\\*"
	reglist["md_italic"] = "\\*[^*]+\\*"
	reglist["md_underscore"] = "__[^_]+__"
	reglist["md_strikethrough"] = "~~[^~]+~~"
	reglist["md_code"] = "`[^`]+`"
	reglist["md_link"] = "\\[[^\\]]*\\]\\([^)]*[^\\\\]\\)"
	reglist["md_spoiler"] = "\\|\\|\\[[^\\]]*\\][^\\|]*\\|\\|"
	
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
	c_vars["debug"] = 0
	c_vars["exit_on_error"] = 1
	c_vars["no_br"] = 0
	c_vars["no_proc"] = 0
	c_vars["curr_line"] = ""
	c_vars["prev_line"] = "<h"
	c_vars["e_nest_lvl"] = 0
	c_vars["inside_pre"] = 0
	c_vars["inside_codeblock"] = 0
}

#
# check if the string is empty / whitespace
# return 1 if it is
#
function is_null(str) {
	gsub(/[ \n\t]/, "", str)
	if (length(str))
		return 0
	else
		return 1
}

#
# return a string with stripped leading and trailing whitespace
#
function strip_sp(str) {
	gsub(/^[ \t]+/, "", str)
	gsub(/[ \t]+$/, "", str)
	return str
}

#
# return a formatted array for debugging
#
function explode_arr(arr,   str,elem) {
	str = "\t"
	for (elem in arr) {
		elem = elem " : \"" arr[elem] "\""
		str = (str == "\t" ? "\t" elem : str "\n\t" elem)
	}
	str = str "\n"
	return str
}

#
# split a string containing surround separated substrings into a
# 1-indexed array with odd entries being text outside of surround
# separators and even entries inside of surround separators.
# returns the count of entries in the resulting array
#
# arguments are as follows:
#   array to write data to
#   input string
#   regex matching a pair of text surrounds
#   length of one side of a surround
#
# example:
#   split_surround(p, "hello %test% world! %aaa%", "%[^%]+%", 1)
# will write the following to p[]:
#   p[1] = "hello "
#   p[2] = "test"
#   p[3] = " world! "
#   p[4] = "aaa"
#   p[5] = ""
# and return 2
#
function split_surround(p, str, sep, slen,   i) {
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
# does this file exist?
# return 1 if so
#
function exists(file,   r) {
	if (is_null(file))
		return 0
	r = getline _ < file
	close(file)
	return (r > -1 ? 1 : 0)
}

#
# complete input path with currently running teg script's path
# and return a correct relative path to the file for later use.
# if input is a full path, return it as it is,
#
function relpath(path,   dir) {
	if (match(path, /^\//) || c_vars["file"] == "stdin")
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
# logt wrapper for debugging where did an error occur
#
function MARK(opt_txt) {
	c_vars["marker_num"] = (c_vars["marker_num"] ? c_vars["marker_num"] : 1)
	logt("MARKER " c_vars["marker_num"] (opt_txt ? " / " opt_txt : ""))
	c_vars["marker_num"] ++
	return
}

#
# escape & < > " ' in text
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
# same as before but skip inline calls and
# some other things that tend to break
#
function escape_html_wrap(str,   parts,ret,i) {
	if (str ~ reglist["call_inline"]) {
		ret = split_surround(parts, str, reglist["call_inline"], 2)
		str = ""
		for (i = 1; i <= ret*2+1; i++) {
			if (i % 2)
				str = str escape_html(parts[i])
			else
				str = str parts[i]
		}
	} else if (str !~ /^!(e|eo|var|exec_raw|exec_fmt)[ \t]/)
		return escape_html(str)
	return str
}

#
# replace a surround with an html tag
#
# arguments are as follows:
#   input string
#   replacement html tag name
#   length of one side of a surround
#   html escape sequence replacing a surround symbol
#
function md_resurround(str, elem, regexp, flen, alt,   parts,ralt,ret,i,k) {
	ret = split_surround(parts, str, regexp, flen)
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
# markdown processor
# call for each line and finish execution with one empty string and c_vars["no_br"] = 1
#
function md_fmt(str) {
	match(str, /^[ \t]*/)
	indent_len = RLENGTH

	#
	# codeblocks
	#
	if (c_vars["inside_codeblock"]) {
		if (c_vars["inside_codeblock"] == 2) {
			c_vars["inside_codeblock"] = 1
			c_vars["inside_pre"] = 1
			return "<pre class=\"cb-pre\"><code class=\"cb-code\">" str
		} else if (str == "```") {
			c_vars["inside_codeblock"] = 0
			c_vars["inside_pre"] = 0
			return "</code></pre>"
		}
		return str
	} else if (str == "```") {
		c_vars["inside_codeblock"] = 2
		return
	}

	#
	# bold, italic, underscode, strikethrough, code
	#
	str = md_resurround(str, "strong", reglist["md_bold"], 2, "&#42;")
	str = md_resurround(str, "em", reglist["md_italic"], 1, "&#42;")
	str = md_resurround(str, "u", reglist["md_underscore"], 2, "&#95;")
	str = md_resurround(str, "s", reglist["md_strikethrough"], 2, "&#126;")
	str = md_resurround(str, "code", reglist["md_code"], 1, "&#96;")

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
	if (str ~ /^---+$/) {
		str = "<hr>"
	}

	#
	# blockquotes
	#
	# current depth
	#
	blockquote_lvl[0] = 0
	if (str ~ /^>+/) {
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
	}
	#
	# depth decreases
	#
	if (blockquote_lvl[0] < blockquote_lvl[1]) {
		blockstr = "</p>"
		for (i = 0; i < blockquote_lvl[1] - blockquote_lvl[0]; i++)
		blockstr = blockstr "</blockquote>"
	}
	#
	# depth stays the same
	#
	if (str ~ /^$/ && blockquote_lvl[0] > 0)
		str = "<br class=\"nl-bq\">"
	if (!is_null(blockstr))
		str = blockstr str
		blockquote_lvl[1] = blockquote_lvl[0]
	#
	# blockquotes end
	#

	#
	# lists (help please this is awful)
	#
	list_type[0] = 0
	list_lvl[0] = 0
	
	if (match(str, /^[ \t]*- /))
		list_type[0] = 1
	else if (match(str, /^[ \t]*[0-9]+\. /))
		list_type[0] = 2

	if (str ~ /^[ \t]*(-|[0-9]+\.) /) {
		start = substr(str, 1, indent_len)
		gsub(/\t/, "  ", start)
		list_lvl[0] = length(start) / 2 + 1
		str = substr(str, RLENGTH + 1)
	}

	liststr = ""

	# list start
	if (list_type[0] && !list_type[1]) {
		list_stack[list_lvl[0]] = list_type[0]
		liststr = (list_type[0] == 1 ? "<ul>" : "<ol>")
		str = "<li>" str "</li>"
	}
	# list end
	else if (!list_type[0] && list_type[1]) {
		# close everything
		for (i = list_lvl[1]; i >= 1; i--) {
			liststr = liststr (list_stack[i] == 1 ? "</ul>" : "</ol>")
			delete list_stack[i]
		}
	}
	# 
	else if (list_type[0] && list_type[1]) {
		# nest++
		if (list_lvl[0] > list_lvl[1]) {
			list_stack[list_lvl[0]] = list_type[0]
			liststr = (list_type[0] == 1 ? "<ul>" : "<ol>")
			str = "<li>" str "</li>"
		}
		# nest--
		else if (list_lvl[0] < list_lvl[1]) {
			# closing up old lists
			for (i = list_lvl[1]; i > list_lvl[0]; i--) {
				liststr = liststr (list_stack[i] == 1 ? "</ul>" : "</ol>")
				delete list_stack[i]
			}
			# no
			if (list_type[0] != list_stack[list_lvl[0]]) {
				liststr = liststr (list_stack[list_lvl[0]] == 1 ? "</ul>" : "</ol>")
				liststr = liststr (list_type[0] == 1 ? "<ul>" : "<ol>")
				list_stack[list_lvl[0]] = list_type[0]
			}
			str = "<li>" str "</li>"
		}
		else {
			# list type change
			if (list_type[0] != list_stack[list_lvl[0]]) {
				liststr = (list_stack[list_lvl[0]] == 1 ? "</ul>" : "</ol>")
				liststr = liststr (list_type[0] == 1 ? "<ul>" : "<ol>")
				list_stack[list_lvl[0]] = list_type[0]
			}
			str = "<li>" str "</li>"
		}
	}

	if (liststr)
		str = liststr str

	list_type[1] = list_type[0]
	list_lvl[1] = list_lvl[0]
	#
	# lists end
	#

	#
	# add br if there's two consecutive \n
	# (with soooome exclusions)
	#
	if (is_null(str) && c_vars["prev_line"] !~ /<\/?(h|ul|ol|pre|p|det)/ && !c_vars["no_br"]) {
		str = "<br class=\"nl\">"
	}
	if (c_vars["no_br"] > 0)
		c_vars["no_br"] --

	#
	# links and images
	#
	while (ix = match(str, reglist["md_link"])) {
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
	# spoilers
	# note: formed like ||[preview text]text inside spoiler||
	#
	while (ix = match(str, reglist["md_spoiler"])) {
		rl = RLENGTH
		spoiler_md = substr(str, ix, rl)

		preview = substr(spoiler_md, 4, index(spoiler_md, "]") - 4)
		text = substr(spoiler_md, length(preview) + 5, rl - length(preview) - 6)

		start = substr(str, 1, ix - 1)
		end = substr(str, ix + rl)

		str = start "<details><summary>" preview "</summary>" text "</details>" end
	}

	c_vars["prev_line"] = str
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
		c_vars["e_nest_lvl"] ++
		return sprintf("<%s%s%s>\n",
			elem_name,
			(elem_class == "_" ? "" : " class=\"" elem_class "\""),
			(elem_props  ? " " elem_props : ""))
	} else {
		logt("closing element: '" elem_name "'")
		elems[elem_name "_" elem_class] = 0
		c_vars["e_nest_lvl"] --
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
	return sprintf("<%s%s%s>",
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
		str = str"\n" "\t<script src=\"" c_vars["script"] "\"></script>"

	reached_start = 1
	c_vars["no_proc"] ++
	str = str"\n" "</head>"
	str = str"\n" "<body>"

	#
	# inline scripts must be in body
	#
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
function calls_exec_fmt(call,   str,line,tmp,i,c) {
	c = 0
	str = ""
	if (is_null(call[0])) {
		logt("empty !exec_fmt command", 3)
		return
	}

	#
	# copying the exec_inc approach here "just in case"
	#
	while((call[0] | getline line) > 0) {
		tmp[c] = line
		c ++
	}
	close(call[0])

	for (i = 0; i < c; i++)
		str = str escape_html(tmp[i]) "\n"

	c_vars["no_proc"] ++
	return "<pre class=\"cb-pre\"><code class=\"cb-code\">" str "</code></pre>"
}

#
# !exec_inc command ...
#
# execute a command and include (tegproc) its output
#
function calls_exec_inc(call,   str,line,tmp,i,c) {
	c = 0
	str = ""
	if (is_null(call[0])) {
		logt("empty !exec_raw command", 3)
		return
	}

	#
	# must separate getline and tegproc else we get a nasty
	# vulnerability on gawk because of pipe propagation
	# (i should probably report this someday???)
	#
	while((call[0] | getline line) > 0) {
		tmp[c] = line
		c ++
	}
	close(call[0])

	for (i = 0; i < c; i++)
		str = str tegproc(tmp[i])

	c_vars["no_br"] ++
	return str
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
	c_vars["no_br"] ++
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
	c_vars["no_br"] ++
	prev_file = c_vars["file"]
	c_vars["file"] = inc_file

	while ((getline line < inc_file) > 0) {
		str = str tegproc(line)
	}
	close(inc_file)

	c_vars["file"] = prev_file
	c_vars["no_proc"] ++
	return str
}

#
# run a call
#
# call["name"] - call name
# call[0]      - concat args
# call[1+]     - args
#
function callproc(str, explicit,   len,call) {
	# I forgot what does this variable do and I don't want to figure it out.
	explicit = (explicit ? 1 : 0)

	if (str ~ /^![^\[]/)
		len = split(substr(str, 2), call, " ")
	else if (explicit)
		len = split(str, call, " ")
	else
		return str

	call["name"] = call[1]
	for (i = 2; i <= len; i++) {
		call[i - 1] = call[i]
		call[0] = call[0] (i > 2 ? " " : "") call[i]
	}
	call[len] = ""

	if (!reached_start && !explicit && call["name"] !~ /(inc|var|start)/) {
		logt("skipping data before start call", 2)
		return
	}

	if (call["name"] == "start")
		str = calls_start(call)
	else if (call["name"] == "e")
		str = calls_e(call)
	else if (call["name"] == "eo")
		str = calls_eo(call)
	else if (call["name"] == "exec_raw")
		str = calls_exec_raw(call)
	else if (call["name"] == "exec_fmt")
		str = calls_exec_fmt(call)
	else if (call["name"] == "exec_inc")
		str = calls_exec_inc(call)
	else if (call["name"] == "var")
		str = calls_var(call)
	else if (call["name"] == "inc")
		str = calls_inc(call)
	else
		logt("unknown call: '" call["name"] "'", 2)

	return str
}

#
# expand inline variables and calls
# inline variable: {$var_name$}
# inline call: {!call_name args ...!}
#
function expand_inline(str,   ret,parts,i) {
	#
	# first expand all variables
	#
	if (str ~ reglist["var_inline"]) {
		ret = split_surround(parts, str, reglist["var_inline"], 2)
		str = ""
		for (i = 1; i <= ret*2+1; i++)
			if (i % 2)
				str = str parts[i]
			else if (substr(parts[i-1], length(parts[i-1]), 1) == "\\")
				str = substr(str, 1, length(str) - 1) "&#123;&#36;" parts[i] "&#36;&#125;"
			else
				str = str c_vars[parts[i]]
	}

	#
	# then run the calls
	#
	if (str ~ reglist["call_inline"]) {
		ret = split_surround(parts, str, reglist["call_inline"], 2)
		str = ""
		for (i = 1; i <= ret*2+1; i++)
			if (i % 2)
				str = str parts[i]
			else if (substr(parts[i-1], length(parts[i-1]), 1) == "\\")
				str = substr(str, 1, length(str) - 1) "&#123;&#33;" parts[i] "&#33;&#125;"
			else
				str = str callproc(parts[i], 1)
	}

	return str
}



#
# the main teg processor function
#
function tegproc(str) {
	c_vars["curr_line"] = str
	
	if (str ~ /^==/ && !c_vars["inside_codeblock"])
		return
	
	if (!reached_start)
		if (str ~ /^!(start|var|inc)/)
			str = callproc(str)
		else if (str ~ /^[ \t]*$/)
			return
		else {
			logt("skipping data before start call", 2)
			return
		}

	if (!c_vars["no_proc"]) {
		if (c_vars["escape"])
			str = escape_html_wrap(str)
		if (!c_vars["inside_codeblock"]) {
			str = expand_inline(str)
			str = callproc(str)
		}
		str = md_fmt(str) (c_vars["curr_line"] !~ /^![^ \t].+/ || c_vars["inside_pre"] ? "\n" : "")
	}
	
	if (c_vars["no_proc"] && c_vars["no_proc"] ~ /^[0-9]+$/)
		c_vars["no_proc"] --
	else if (c_vars["curr_line"] ~ c_vars["no_proc"])
		c_vars["no_proc"] = 0

	c_vars["prev_line"] = str
	gsub(/\\\\/, "\\", str)
	return str
}

END {
	if (reached_start) {
		# cleanly finish all pending markdown work
		c_vars["no_br"] ++
		md_fmt("")
		print "</body>"
		print "</html>"
	}
}

#
# the awk's "main" function
#
{
	printf("%s", tegproc($0))
}
