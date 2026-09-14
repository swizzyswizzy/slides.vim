" Mini-konfig okna podglądu (drugi proces Vima).
" Ładowany przez: vim -u preview.vimrc --noplugin

set nocompatible
set noswapfile
set nobackup
set nowritebackup
set hidden
set autoread
set laststatus=0
set showtabline=0
set noruler
set noshowcmd
set noshowmode
set cmdheight=1
set nonumber
set norelativenumber
set foldcolumn=0
set nowrap
set nolist
set nocursorline
set nocursorcolumn
set nomodifiable
set nomodified
if exists('&signcolumn')
  set signcolumn=no
endif

file [slides-preview]

nnoremap <silent> q    :qa!<CR>
nnoremap <silent> <Esc> :qa!<CR>

function! SlidesPreviewReload(timer) abort
  silent! checktime
endfunction

if has('timers')
  call timer_start(250, 'SlidesPreviewReload', {'repeat': -1})
endif
