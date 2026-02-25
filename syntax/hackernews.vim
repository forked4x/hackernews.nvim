if exists('b:current_syntax')
  finish
endif

" Inline formatting: conceal tags, apply highlight
syn region hnItalic matchgroup=hnFormatTag start="<i>" end="</i>" concealends contains=hnBold,hnUnderline,hnFoldClose
syn region hnBold matchgroup=hnFormatTag start="<b>" end="</b>" concealends contains=hnItalic,hnUnderline,hnFoldClose
syn region hnUnderline matchgroup=hnFormatTag start="<u>" end="</u>" concealends contains=hnItalic,hnBold,hnFoldClose

hi hnItalic cterm=italic gui=italic
hi hnBold cterm=bold gui=bold
hi hnUnderline cterm=underline gui=underline

" Conceal [metadata] at end of line (only within parent groups)
syn match hnConcealed /\[.\{-}\]\( {{{\)\?$/ contained conceal

" Conceal fold close markers }}} (top-level, for content lines)
syn match hnFoldClose /\( }}}\)\+$/ conceal

" Header: " Y  Hacker News [url]"
syn match hnLogo / Y / contained
syn match hnTitle /Hacker News\( > .\+\)\?\ze \[/ contained
syn match hnHeaderLine /^ Y  Hacker News.\+\[.\+\]$/ contains=hnLogo,hnTitle,hnConcealed

" Frontpage: rank prefix " 1. " or "10. "
syn match hnRank /^ \?\d\+\.\s/ contained

" Frontpage: domain in parens before concealed [url]
syn match hnDomain / ([^()]*)\ze \[/ contained

" Frontpage: title line (contains rank, domain, concealed url)
syn match hnTitleLine /^ \?\d\+\..\+$/ contains=hnRank,hnDomain,hnConcealed

" Frontpage: subtitle line (4-space indent, ends with [item_id])
syn match hnSubtitle /^    \S.\+\[\d\+\]$/ contains=hnConcealed

" Comments: info/header line (ends with [item_id] {{{)
syn match hnCommentInfo /^.\+\[\d\+\] {{{$/ contains=hnConcealed

" Comments: story header title (no rank prefix, ends with concealed URL)
syn match hnStoryHeader /^\%(\d\+\. \)\@!\S.\+\[https\?:\/\/.\+\]$/ contains=hnDomain,hnConcealed

" Comments: story header subtitle (starts with digit, ends with [item_id])
syn match hnStorySubtitle /^\d.\+\[\d\+\]$/ contains=hnConcealed

hi hnLogo guifg=#ffffff guibg=#ff6600 gui=bold ctermfg=15 ctermbg=166 cterm=bold
hi hnTitle guifg=#ff6600 gui=bold ctermfg=166 cterm=bold
hi hnStoryHeader guifg=#ff6600 cterm=bold gui=bold ctermfg=166

hi def link hnRank Comment
hi def link hnDomain Comment
hi def link hnSubtitle Comment
hi def link hnStorySubtitle Comment
hi def link hnCommentInfo Comment

let b:current_syntax = 'hackernews'
