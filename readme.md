# teg
teg is a something I made more of as a joke that has grown into a
completely usable web templating language made entirely in AWK.

There's bugs. Mostly ones that I don't know about.
Some I know of, but won't fix because that would require
adding hundreds more lines of code to teg.
*(example: inline calls cannot contain a `!` inside)*

# Syntax documentation
Refer to `docs.teg`.

# How do I use this
manually convert a .teg file into .html:
```
./teg.awk file.teg > output.html
```

or use as cgi: (lighttpd example)
```
cgi.assign = ( ".teg" => "/opt/teg/teg.awk" )
index-file.names = ( "index.html", "index.teg", "main.teg" )
static-file.exclude-extensions = ( ".teg" )
```
... and now .teg files will be automatically formatted 
(as long as you have teg in /opt/teg/teg.awk)