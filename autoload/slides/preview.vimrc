" Mini-konfig okna podglądu (drugi proces Vima).
" Ładowany przez: vim -u preview.vimrc --noplugin
" Bufor MUSI zostać przy pliku na dysku — inaczej checktime nic nie widzi.

set nocompatible
set noswapfile
set nobackup
set nowritebackup
set hidden
set autoread
set laststatus=1
set statusline=\ PODGLAD\ NASTEPNEGO\ %<%f
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
if exists('&signcolumn')
  set signcolumn=no
endif

nnoremap <silent> q     :qa!<CR>
nnoremap <silent> <Esc> :qa!<CR>

function! SlidesPreviewReload(timer) abort
  if !&modified
    silent! checktime
  endif
endfunction

augroup SlidesPreview
  autocmd!
  autocmd BufReadPost,BufNewFile * setlocal nomodifiable nomodified autoread
  autocmd FileChangedShell * let v:fcs_choice = 'reload'
  autocmd FileChangedShellPost * setlocal nomodifiable nomodified
augroup END

if has('timers')
  call timer_start(200, 'SlidesPreviewReload', {'repeat': -1})
endif
