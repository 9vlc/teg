![teg!](extra/teg.png)
----
teg is a something I made more of as a joke that has grown into a
completely usable web templating language made entirely in AWK.

There's bugs. Mostly ones that I don't know about.
Some I know of, but won't fix because that would require
adding hundreds more lines of code to teg.
*(example: inline calls cannot contain a `!` inside)*

# Documentation
Refer to `docs.teg` (convert to html using `./teg docs.teg > docs.html`)

# How do I use this
Manually convert a .teg file into .html:
```
./teg.awk file.teg > output.html
```

Or use as CGI: (lighttpd)
```
cgi.assign = ( ".teg" => "/opt/teg/teg.awk" )
index-file.names = ( "index.html", "index.teg", "main.teg" )
static-file.exclude-extensions = ( ".teg" )
```
... and now .teg files will be automatically formatted 
(as long as you have teg in /opt/teg/teg.awk)

## Usage as an AWK library
Since the v1.8 update, teg can be used as a library in GAWK.

Read up on the latest chapter in the `docs.teg` file and for an example of
library usage check [extra/library_use.awk](extra/library_use.awk)

# Pull requests
I would be very thankful!
teg has grown to be a giant mess of a project with me just stacking whatever I need
on top of what I've made before.

But please, don't be afraid! If you want to add something new, go on and do it!
