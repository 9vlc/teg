# The README
## What's teg?
teg is a small (~500 LOC) portable web "[anti-framework](https://werc.cat-v.org)" foundation made in AWK,
compatible with pretty much all AWKs out there, so you can even use teg on [Plan 9](https://en.wikipedia.org/wiki/Plan_9_from_Bell_Labs).


teg is meant to be a minimal building block for your full website; it only acts as a page generator.
You can piece together teg with your own scripts and programs to, for example, make a full-on [CGI](https://en.wikipedia.org/wiki/Common_Gateway_Interface) system.
teg can be used with a [Makefile](https://en.wikipedia.org/wiki/Make_(software)) to generate a static site from a list of `.teg` files.


The current implementation of teg consists of several discrete parts:
- teg processor
- Markdown processor
- Call and variable processor

## Naming
teg is always typed lowercase.

teg is named as a reference to the Russian name for graffiti tags *(тег, теггинг)* and their crudeness, just like teg itself.

## Syntax
The syntax of teg is all over the place. It is a mix of a dialect of Markdown, calls, variables and comments.

### Comments
Comments are defined with two equals signs at the start of a line:
```
== This is a comment
   == This is NOT a comment
```
All comments are skipped.

### Calls
Calls are defined with an exclamation mark at the start of a line:
```
!exec_raw echo 'Hello, World!'
```
If the call exists, it will be executed, and the line replaced with the call's return.

The current implemented calls are:

---
> !**var** *variable*=*value*

Set *variable* to *value*

If *value* is not set but an equals sign exists, clear *variable*

---
> !**start**

Declare the start of the webpage.

You can only use !**inc** and !**var** before !**start**.

---
> !**exec_raw** *command*

Run a *command* in your system's command interpreter and give its output to the Markdown processor.

---
> !**exec_fmt** *command*

Run a *command* and paste its output as a code block. Disables the Markdown processor for the contents of the code block.

---
> !**inc** *file*

Include a file.

---
> !**e** *element* *class* *options*

Open an HTML tag on first call, remember the class, and close the tag on the second call for the same class.

If *class* is "_", the HTML tag does not receive a class.

The *options* get passed to the HTML tag like so: `!e div _ style="font-size: 90%;"` -> `<div style="font-size: 90%;">`

---
> !**eo** *element* *class* *options*

Same as !**e**; just don't remember the class and don't close the element. Only use on self-closing tags.

---

### Inline calls
The following syntax can be used to include a call or a variable without splitting a line:
- For variables: `\{$variable$}`
- For calls: `\{!call!}`

The following is an example of using inline calls to create a page that displays your Linux distro name:
```
!var osname={!exec_raw . /etc/os-release;echo $PRETTY_NAME!}
!start
My current distro is `{$osname$}`
```

Inline calls can be nested:
```
!var ls_args=-lF
!start
ls output: {!exec_fmt ls {$ls_args$}!}
```

## Variables
teg has some built-in variables that you can read for information or set to change behavior:

---
> **file**

File that is currently being processed.

---
> **title**=**file**

Page title.

---
> **description**

Page description (appears in search engines).

---
> **lang**=*en-US*

Page locale.

---
> **color_chrome**

Browser style color (only for mobile).

---
> **icon**

Favicon.

---
> **style**

External CSS stylesheet to reference.

---
> **style_inline**

CSS stylesheet to include in HTML.

---
> **script**

External JS to reference.

---
> **script_inline**

Inline JS to include in HTML.

---
> **debug**=*1*

Enable / disable debug logging.

---
> **exit_on_error**=*1*

Abort processing and exit on error.

---
> **no_br**=*0*

Ignore line breaks for the next N lines.

---
> **no_proc**=*0*

Halt processing for the next N lines.

---
> **current_line**

Current line, unprocessed.

---
> **prev_line**

Previous processed line.

---
> **e_nest_lvl**=*0*

Current element nesting level.

---
> **inside_pre**=*0*

Are we inside preformatted text?

---
> **inside_codeblock**=*0*

Are we inside a codeblock?

---
### Markdown
teg's markdown is relatively close to the one you are familiar with, except for some missing features and convenience changes, notably:

---
> **Spoilers**

```
||[Click me]Boo!||
```

<details>
   <summary>Click me</summary>
   Boo!
</details>

---
> **Modified newline behavior**

```
Line 1
Same line

Line 2


Line 4?
```
formats as
```
Line 1 Same line
Line 2

Line 4?
```
---
> **Strikethrough text**

```
~~strikethrough!~~
```
~~strikethrough!~~

---

Escaping with \\ is implemented manually for each element because of some limitations,
so don't expect escapes to work as expected.
