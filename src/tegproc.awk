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
# are met:
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
		file = "stdin"
	else
		file = ARGV[1]
	
	reached_data = 0
	reached_start = 0
	inside_codeblock = 0
	blockquote_lvl[0] = 0
	blockquote_lvl[1] = 0
	prev_str = "<hnull"
	
	c_vars["escape"] = 1
	c_vars["title"] = file
	c_vars["description"] = 0
	c_vars["lang"] = "en-US"
	c_vars["icon"] = 0
	c_vars["style"] = 0
	c_vars["script"] = 0
	c_vars["color_chrome"] = 0
	c_vars["debug"] = 1

	print "<!DOCTYPE html>"
	print "<!-- Generated with teg: https://github.com/9vlc/teg -->"
}

function dirname(path) {
    sub(/[^\/]*$/, "", path)
    return (path ? path : "./")
}

function dlog(txt) {
	if (c_vars["debug"])
		print "!!!DEBUG!!! " txt > "/dev/stderr"
	else
		return 1
}

function escape_html(str) {
	gsub(/&/, "\\&amp;", str);
	gsub(/"/, "\\&quot;", str);
	gsub(/'/, "\\&apos;", str);
	gsub(/</, "\\&lt;", str);
	if (str !~ /^>+( |$)/)
		gsub(/>/, "\\&gt;", str);
	return str;
}

function md_resurround(str, elem, regexp, flen) {
	while (i = match(str, regexp)) {
		start = substr(str, 1, i - 1)
		mid = substr(str, i + flen, RLENGTH - flen * 2)
		end = substr(str, i + RLENGTH)
		str = start "<"elem">" mid "</"elem">" end
	}
	return str
}

#
# scary
#
# TODO: ordered lists, unordered lists
#
function md_fmt(str) {
	#
	# codeblocks
	#
	if (inside_codeblock) {
		if (inside_codeblock == 2) {
			inside_codeblock = 1
			return "<pre><code>" str
		} else if (str == "```") {
			inside_codeblock = 0
			return "</code></pre>"
		}
		return str
	} else if (str == "```") {
		inside_codeblock = 2
		return
	}

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
		str = "<br class=\"hrule\">"

	#
	# blockquotes
	#
	# current depth
	#
	if (str ~ /^>+/) {
		match(str, /^>+/)
		blockquote_lvl[0] = RLENGTH
    	if (blockquote_lvl[0] > 0)
    		str = substr(str, blockquote_lvl[0] + 2)
	} else
		blockquote_lvl[0] = 0
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
	} else {
		if (str ~ /^$/ && blockquote_lvl[0] > 0)
			str = "<br class=\"nl-bq\">"
	}
	str = blockstr str
	blockquote_lvl[1] = blockquote_lvl[0]
	#
	# blockquotes end
	#

	#
	# add br if there's two consecutive \n
	#
	if (str ~ /^$/ && prev_str !~ /(<\/?h[1-6]|<br)/) {
		str = "<br class=\"nl\">"
		dlog(prev_str)
	}

	#
	# bold, italic, underscode, strikethrough
	#
	str = md_resurround(str, "strong", "\\*\\*[^*]+\\*\\*", 2)
	str = md_resurround(str, "em", "\\*[^*]+\\*", 1)
	str = md_resurround(str, "u", "__[^_]+__", 2)
	str = md_resurround(str, "s", "~~[^~]+~~", 2)
	str = md_resurround(str, "code", "`[^`]+`", 1)

	#
	# links and images
	#
	while (ix[0] = match(str, /\[.*\]\(.*\)/)) {
		is_image = 0
		rl[0] = RLENGTH
		link_md = substr(str, ix[0], rl[0])
		
		if (substr(str, ix[0] - 1, 1) == "!")
			is_image = 1
		
		start = substr(str, 1, ix[0] - 1)

		text = substr(link_md, 2, match(link_md, "]") - 2)
		link = substr(link_md, length(text) + 4, rl[0] - length(text) - 4)
		end = substr(str, ix[0] + rl[0])

		if (is_image)
			str = substr(start, 1, length(start) - 1) "<img alt=\""text"\" src=\""link"\">" end
		else
			str = start "<a href=\""link"\">"text"</a>" end
	}

	prev_str = str
	return str
}


!/^==/ && !/^![^\[]/ {
	if ($0 !~ /^[ \t]*$/)
		reached_data = 1
	if (!reached_data)
		next
	if (!reached_start) {
		print "warning: skipping data before start call" > "/dev/stderr"
		next
	}

	if (c_vars["escape"])
		$0 = escape_html($0)

	$0 = md_fmt($0)

	print $0
}

#
# calls
#
/^![^\[]/ {
	$0 = substr($0, 2)
	call = $1
	$1 = ""
	sub(/^[ \t]+/, "", $0)
	
	if (!reached_start && call !~ /(inc|var|start)/) {
		print "warning: skipping data before start call" > "/dev/stderr"
		next
	}

	#
	# element
	#
	if (call == "e") {
		# TODO: hell
	#
	# place the head part of the website
	#
	} else if (call == "start") {
		if (reached_start)
			next
		print "<html lang=\"" c_vars["lang"] "\">"
		print "<head>"
		print "  <meta charset=\"UTF-8\"/>"
		if (c_vars["title"])
			print "  <title>" c_vars["title"] "</title>"
		if (c_vars["description"])
			print "  <meta name=\"description\" content=\"" c_vars["description"] "\"/>"
		if (c_vars["color_chrome"])
			print "  <meta name=\"theme-color\" content=\"" c_vars["color_chrome"] "\"/>"
		if (c_vars["icon"])
			print "  <link rel=\"icon\" href=\"" c_vars["icon"] "\"/>"
		if (c_vars["style"])
			print "  <link rel=\"stylesheet\" type=\"text/css\" href=\"" c_vars["style"] "\">"
		if (c_vars["script"])
			print "  <script src=\"" c_vars["script"] "\">"
		print "</head>"
		print "<body>"
		reached_start = 1
	#
	# raw command output
	#
	} else if (call == "exec_raw") {
		cmd = $0
		while((cmd | getline line) > 0) {
			print line
		}
		close(cmd)
	#
	# codeblock command output
	#
	} else if (call == "exec_fmt") {
		cmd = $0
		printf("<pre><code>")
		while((cmd | getline line) > 0) {
			print escape_html(line)
		}
		close(cmd)
		printf("</code></pre>")
		# don't add a newline that may appear after the codeblock
		prev_str = "<br"
	#
	# include a file
	#
	} else if (call == "inc") {
		print "warning: includes not implemented" > "/dev/stderr"
		next
	#
	# set a variable
	#
	} else if (call == "var") {
		match($0, /[^=]+/)
		key = substr($0, 1, RLENGTH)
		sub(/^[ \t]+/, "", key)
		value = substr($0, RLENGTH + 2)
		if (value ~ /^-?[0-9]+$/)
			c_vars[key] = value + 0
		else
			c_vars[key] = value

		dlog("'"key"' ""'"value"'")
	}
}

END {
	if (reached_start) {
		print "</body>"
		print "</html>"
	}
}
