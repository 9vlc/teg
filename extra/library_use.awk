#
# Example usage of teg as a library:
#   Basic markdown to html converter with teg functionality stripped
#

# Must define TEG_AS_LIBRARY = 1 before including
BEGIN { TEG_AS_LIBRARY = 1 }
@include "teg.awk"

#
# Initialization
#
BEGIN {
	TEG_init()
	
	# Set some variables
	# (you can also do it with TEG_proc("!var ..."))
	TEG_c_vars["title"] = "Converted markdown"
	print TEG_proc("!start")
}

#
# On script exit
#
END {
	print TEG_end()
}

#
# And for each input line
#
{
	print TEG_md_fmt($0)
}
