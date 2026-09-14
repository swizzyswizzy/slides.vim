if exists('b:current_syntax')
  finish
endif

" '~' jest atomem regex w Vimie (|/~|) — każdą tyldę trzeba escapować.
syntax match slidesSeparator /^\~\~\~\~$/
syntax match slidesHeading /^\s*#\+\s.*$/
syntax match slidesBullet /^\s*[-*+]\s/
syntax match slidesNumbered /^\s*\d\+\.\s/
syntax region slidesFence start=/^\s*```/ end=/^\s*```/

highlight default slidesSeparator ctermfg=8 guifg=#555555 cterm=bold gui=bold
highlight default slidesHeading ctermfg=4 guifg=#6ab0ff cterm=bold gui=bold
highlight default slidesBullet ctermfg=2 guifg=#7dcf8a
highlight default slidesNumbered ctermfg=2 guifg=#7dcf8a
highlight default slidesFence ctermfg=5 guifg=#c792ea

let b:current_syntax = 'slides'
