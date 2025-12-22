" Vim syntax file
" Language:     teg
" Maintainer:   ninevlc
" Filenames:    *.teg
" Last Change: 2025-12-21

" experimental vim syntax file for teg.
" do not install.

if exists("b:current_syntax")
  finish
endif

runtime! syntax/markdown.vim
unlet! b:current_syntax
syn case match

syn match tegWhatever "^[\^ ]+"
syn match tegComment "^==.*$"
syn match tegCall "^![A-Za-z0-9_]\w*"
syn match tegCallInclude "!inc\w*"
syn match tegCallVar "!var\w*"

syn region tegInlineVar keepend
	\ matchgroup=tegInlineVarDelim
	\ start="{\$"
	\ end="\$}"
	\ contains=tegWhatever

syn region tegInlineCall keepend
	\ matchgroup=tegInlineCallDelim
	\ start="{!"
	\ end="!}"
	\ contains=tegWhatever

hi def link tegComment         Comment
hi def link tegCall            Function
hi def link tegCallInclude     Include
hi def link tegCallVar         Constant

hi def link tegInlineVarDelim  Constant
hi def link tegInlineVar       Constant
hi def link tegInlineCallDelim Function
hi def link tegInlineCall      Function

let b:current_syntax = "teg"
