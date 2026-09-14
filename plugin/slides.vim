" slides.vim - prezentacje pełnoekranowe z podglądem na drugim monitorze
" Tylko Vim 8+ (nie Neovim). Separator slajdów: linia ~~~~

if exists('g:loaded_slides')
  finish
endif
let g:loaded_slides = 1

if has('nvim')
  finish
endif

if v:version < 800
  echohl WarningMsg
  echom 'slides.vim wymaga Vima 8.0 lub nowszego'
  echohl None
  finish
endif

command! -nargs=0 SlidesStart  call slides#start()
command! -nargs=0 Slides       call slides#start()
command! -nargs=0 SlidesNext   call slides#next()
command! -nargs=0 SlidesPrev   call slides#prev()
command! -nargs=1 SlidesGoto   call slides#goto(<args>)
command! -nargs=0 SlidesQuit   call slides#quit()
command! -nargs=0 SlidesTogglePreview call slides#preview#toggle()
command! -nargs=0 SlidesResize call slides#resize_current()

nnoremap <silent> <Plug>(slides-start)  :call slides#start()<CR>
nnoremap <silent> <Plug>(slides-next)   :call slides#next()<CR>
nnoremap <silent> <Plug>(slides-prev)   :call slides#prev()<CR>
nnoremap <silent> <Plug>(slides-quit)   :call slides#quit()<CR>
