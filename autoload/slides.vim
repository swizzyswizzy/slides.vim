" autoload/slides.vim - silnik prezentacji (Vim 8+, nie Neovim)
" Separator: \n~~~~\n  (linia złożona wyłącznie z czterech tyld)

let s:state = {
      \ 'active': 0,
      \ 'slides': [],
      \ 'index': 0,
      \ 'source_bufnr': -1,
      \ 'source_winid': 0,
      \ 'present_bufnr': -1,
      \ 'saved': {},
      \ 'orig_columns': 0,
      \ 'orig_lines': 0,
      \ 'orig_winpos': [0, 0],
      \ }
let s:resizing = 0
let s:last_csi = [0, 0]

function! slides#is_active() abort
  return get(s:state, 'active', 0)
endfunction

function! slides#current_index() abort
  return get(s:state, 'index', 0)
endfunction

function! slides#slide_count() abort
  return len(get(s:state, 'slides', []))
endfunction

function! slides#get_slide(idx) abort
  if a:idx < 0 || a:idx >= len(s:state.slides)
    return []
  endif
  return copy(s:state.slides[a:idx])
endfunction

" ---------------------------------------------------------------------------
" Konfiguracja
" ---------------------------------------------------------------------------

function! s:opt(name, default) abort
  return get(g:, a:name, a:default)
endfunction

function! s:separator_line() abort
  " Dosłowna linia-separator. W Vimie '~' jest atomem regex (/~),
  " dlatego NIE używamy split(..., '\n~~~~\n').
  return s:opt('slides_separator_line', '~~~~')
endfunction

function! s:trim_slide(lines) abort
  let l:slide = copy(a:lines)
  while len(l:slide) && l:slide[0] =~# '^\s*$'
    call remove(l:slide, 0)
  endwhile
  while len(l:slide) && l:slide[-1] =~# '^\s*$'
    call remove(l:slide, -1)
  endwhile
  return l:slide
endfunction

" ---------------------------------------------------------------------------
" Parsowanie
" ---------------------------------------------------------------------------

function! slides#parse_buffer(...) abort
  let l:bufnr = a:0 ? a:1 : bufnr('%')
  let l:lines = getbufline(l:bufnr, 1, '$')
  return slides#parse_lines(l:lines)
endfunction

function! slides#parse_lines(lines) abort
  let l:sep = s:separator_line()
  let l:slides = []
  let l:cur = []
  for l:raw in a:lines
    let l:line = substitute(l:raw, '\r$', '', '')
    if l:line ==# l:sep
      let l:slide = s:trim_slide(l:cur)
      if !empty(l:slide)
        call add(l:slides, l:slide)
      endif
      let l:cur = []
    else
      call add(l:cur, l:line)
    endif
  endfor
  let l:slide = s:trim_slide(l:cur)
  if !empty(l:slide)
    call add(l:slides, l:slide)
  endif
  return l:slides
endfunction

function! s:max_width(lines) abort
  let l:w = 0
  for l:line in a:lines
    let l:w = max([l:w, strdisplaywidth(l:line)])
  endfor
  return l:w
endfunction

function! s:deck_max_width() abort
  let l:w = 0
  for l:slide in s:state.slides
    let l:w = max([l:w, s:max_width(l:slide)])
  endfor
  return l:w
endfunction

function! s:deck_max_height() abort
  let l:h = 0
  for l:slide in s:state.slides
    let l:h = max([l:h, len(l:slide)])
  endfor
  return l:h
endfunction

" ---------------------------------------------------------------------------
" Pomiar ekranu
" ---------------------------------------------------------------------------

function! s:screen_cells() abort
  " Maksymalny rozsądny rozmiar: bieżący ekran albo bardzo duży fallback
  return [max([&lines, 24]), max([&columns, 80])]
endfunction

function! s:display_geometry() abort
  " [max_cols, max_lines] ograniczenia użytkownika / ekranu
  let l:max_c = s:opt('slides_max_columns', 0)
  let l:max_l = s:opt('slides_max_lines', 0)
  let [l:scr_l, l:scr_c] = s:screen_cells()
  if l:max_c <= 0
    let l:max_c = l:scr_c
  endif
  if l:max_l <= 0
    let l:max_l = l:scr_l
  endif
  return [l:max_c, l:max_l]
endfunction

" ---------------------------------------------------------------------------
" Zmiana rozmiaru okna terminala / GUI
" ---------------------------------------------------------------------------

function! slides#resize_to(cols, lines) abort
  let l:cols = max([s:opt('slides_min_columns', 40), a:cols])
  let l:rows = max([s:opt('slides_min_lines', 12), a:lines])
  let [l:max_c, l:max_l] = s:display_geometry()
  let l:cols = min([l:cols, l:max_c])
  let l:rows = min([l:rows, l:max_l])
  let l:cols = max([l:cols, 20])
  let l:rows = max([l:rows, 8])

  if s:resizing
    return [l:cols, l:rows]
  endif
  if has('gui_running')
    if &columns == l:cols && &lines == l:rows
      return [l:cols, l:rows]
    endif
    let s:resizing = 1
    try
      silent! execute 'set columns=' . l:cols
      silent! execute 'set lines=' . l:rows
    finally
      let s:resizing = 0
    endtry
  else
    " W TUI nie ruszamy &columns/&lines — to odpala VimResized w pętli.
    " Tylko CSI 8 t (fizyczne okno); Vim dowie się o rozmiarze z terminala.
    if s:last_csi[0] != l:rows || s:last_csi[1] != l:cols
      let s:last_csi = [l:rows, l:cols]
      let s:resizing = 1
      try
        call s:csi_resize(l:rows, l:cols)
      finally
        let s:resizing = 0
      endtry
    endif
  endif
  return [l:cols, l:rows]
endfunction

function! s:csi_resize(rows, cols) abort
  let l:seq = printf("\e[8;%d;%dt", a:rows, a:cols)
  if exists('*echoraw')
    silent! call echoraw(l:seq)
    return
  endif
  if filewritable('/dev/tty')
    silent! call writefile([l:seq], '/dev/tty', 'b')
    return
  endif
endfunction

function! s:csi_fullscreen(on) abort
  " CSI 10 ; 1 t = pełny ekran, CSI 10 ; 2 t = maksymalizacja,
  " CSI 9 ; 1 t = maximize window (xterm)
  if has('gui_running')
    if a:on
      if has('gui_macvim')
        silent! set fullscreen
      elseif exists(':simalt') && has('win32')
        silent! simalt ~x
      endif
    else
      if has('gui_macvim')
        silent! set nofullscreen
      endif
    endif
    return
  endif
  let l:seq = a:on ? "\e[10;1t" : "\e[10;0t"
  if exists('*echoraw')
    silent! call echoraw(l:seq)
  elseif filewritable('/dev/tty')
    silent! call writefile([l:seq], '/dev/tty', 'b')
  endif
endfunction

function! slides#fit_slide(lines) abort
  let l:pad_x = s:opt('slides_pad_x', 6)
  let l:pad_y = s:opt('slides_pad_y', 3)
  let l:mode = s:opt('slides_resize_mode', 'current')
  if l:mode ==# 'max'
    let l:w = s:deck_max_width()
    let l:h = s:deck_max_height()
  else
    let l:w = s:max_width(a:lines)
    let l:h = len(a:lines)
  endif
  " +1 na cmdline, +1 na ewentualny status jeśli włączony
  let l:status = (s:opt('slides_show_status', 1) ? 1 : 0)
  let l:cols = l:w + 2 * l:pad_x
  let l:rows = l:h + 2 * l:pad_y + l:status + 1
  return slides#resize_to(l:cols, l:rows)
endfunction

function! slides#resize_current() abort
  if !s:state.active || s:resizing
    return
  endif
  let s:last_csi = [0, 0]
  call s:render()
endfunction

function! s:on_vim_resized() abort
  " Tylko przerysuj w aktualnym rozmiarze — NIE wysyłaj CSI (pętla + miganie).
  if !s:state.active || s:resizing
    return
  endif
  call s:paint(&columns, &lines)
endfunction

" ---------------------------------------------------------------------------
" Render slajdu
" ---------------------------------------------------------------------------

function! s:center_lines(lines, width, height) abort
  let l:pad_x = s:opt('slides_pad_x', 6)
  let l:out = []
  let l:maxw = s:max_width(a:lines)
  let l:left = s:opt('slides_center_h', 1)
        \ ? max([0, (a:width - l:maxw) / 2])
        \ : l:pad_x
  for l:line in a:lines
    call add(l:out, repeat(' ', l:left) . l:line)
  endfor
  if s:opt('slides_center_v', 1)
    let l:top = max([0, (a:height - len(l:out) - 1) / 2])
    let l:out = repeat([''], l:top) + l:out
  endif
  return l:out
endfunction

function! s:status_text() abort
  let l:i = s:state.index + 1
  let l:n = len(s:state.slides)
  let l:title = s:opt('slides_title', '')
  if empty(l:title) && s:state.source_bufnr > 0
    let l:title = fnamemodify(bufname(s:state.source_bufnr), ':t')
  endif
  let l:left = empty(l:title) ? 'SLIDES' : l:title
  let l:right = printf('%d / %d', l:i, l:n)
  return [l:left, l:right]
endfunction

function! s:render() abort
  if !s:state.active || s:state.present_bufnr < 0
    return
  endif
  let l:slide = slides#get_slide(s:state.index)
  let [l:cols, l:rows] = slides#fit_slide(l:slide)
  " Po CSI terminal może jeszcze mieć stary rozmiar — maluj do max(cel, aktualny).
  call s:paint(max([l:cols, &columns]), max([l:rows, &lines]))
  call slides#preview#update(s:state)
endfunction

function! s:paint(cols, rows) abort
  if !s:state.active || s:state.present_bufnr < 0
    return
  endif
  let l:slide = slides#get_slide(s:state.index)
  let l:cols = max([a:cols, 1])
  let l:rows = max([a:rows, 1])
  let l:body = s:center_lines(l:slide, l:cols, l:rows - 1)

  if s:opt('slides_show_status', 1)
    let [l:left, l:right] = s:status_text()
    let l:gap = max([1, l:cols - strdisplaywidth(l:left) - strdisplaywidth(l:right) - 2])
    let l:status = ' ' . l:left . repeat(' ', l:gap) . l:right . ' '
    while len(l:body) < l:rows - 2
      call add(l:body, '')
    endwhile
    if len(l:body) > l:rows - 2
      let l:body = l:body[: l:rows - 3]
    endif
    call add(l:body, '')
    call add(l:body, l:status)
  endif

  call s:with_present_buf('call s:write_lines(' . string(l:body) . ')')
  silent! normal! gg
endfunction

function! s:write_lines(lines) abort
  setlocal modifiable noreadonly
  silent %delete _
  call setline(1, a:lines)
  setlocal nomodifiable nomodified
endfunction

function! s:with_present_buf(cmd) abort
  if bufnr('%') == s:state.present_bufnr
    execute a:cmd
    return
  endif
  let l:prev = bufnr('%')
  execute 'keepalt buffer' s:state.present_bufnr
  execute a:cmd
  if bufexists(l:prev)
    execute 'keepalt buffer' l:prev
  endif
endfunction

" ---------------------------------------------------------------------------
" Opcje prezentacji (fullscreen look)
" ---------------------------------------------------------------------------

function! s:apply_present_options() abort
  let s:state.saved = {
        \ 'guioptions': &guioptions,
        \ 'laststatus': &laststatus,
        \ 'showtabline': &showtabline,
        \ 'cmdheight': &cmdheight,
        \ 'ruler': &ruler,
        \ 'number': &number,
        \ 'relativenumber': &relativenumber,
        \ 'signcolumn': &signcolumn,
        \ 'wrap': &wrap,
        \ 'list': &list,
        \ 'cursorline': &cursorline,
        \ 'cursorcolumn': &cursorcolumn,
        \ 'showcmd': &showcmd,
        \ 'showmode': &showmode,
        \ 'scrolloff': &scrolloff,
        \ 'foldcolumn': &foldcolumn,
        \ 'colorcolumn': &colorcolumn,
        \ 'conceallevel': &conceallevel,
        \ 'hidden': &hidden,
        \ 'columns': &columns,
        \ 'lines': &lines,
        \ }
  if has('gui_running')
    try
      let s:state.orig_winpos = [getwinposx(), getwinposy()]
    catch
      let s:state.orig_winpos = [0, 0]
    endtry
  endif
  let s:state.orig_columns = &columns
  let s:state.orig_lines = &lines

  set laststatus=0
  set showtabline=0
  set cmdheight=1
  set noshowcmd
  set noshowmode
  set noruler
  set hidden
  if has('gui_running')
    set guioptions-=T
    set guioptions-=m
    set guioptions-=r
    set guioptions-=L
    set guioptions-=b
  endif

  if s:opt('slides_fullscreen', 0)
    call s:csi_fullscreen(1)
  endif
endfunction

function! s:restore_options() abort
  call s:csi_fullscreen(0)
  let l:s = s:state.saved
  if empty(l:s)
    return
  endif
  let &guioptions = get(l:s, 'guioptions', &guioptions)
  let &laststatus = l:s.laststatus
  let &showtabline = l:s.showtabline
  let &cmdheight = l:s.cmdheight
  let &ruler = l:s.ruler
  let &showcmd = l:s.showcmd
  let &showmode = l:s.showmode
  let &hidden = l:s.hidden
  silent! execute 'set columns=' . get(l:s, 'columns', &columns)
  silent! execute 'set lines=' . get(l:s, 'lines', &lines)
  if has('gui_running') && len(s:state.orig_winpos) == 2
    silent! execute 'winpos' s:state.orig_winpos[0] s:state.orig_winpos[1]
  endif
endfunction

function! s:prepare_present_buffer() abort
  if s:state.present_bufnr > 0 && bufexists(s:state.present_bufnr)
    execute 'keepalt buffer' s:state.present_bufnr
  else
    enew
    let s:state.present_bufnr = bufnr('%')
  endif
  silent! file [slides]
  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nobuflisted
  setlocal nomodifiable
  setlocal nomodified
  setlocal nonumber
  setlocal norelativenumber
  if exists('&signcolumn')
    setlocal signcolumn=no
  endif
  setlocal foldcolumn=0
  setlocal nowrap
  setlocal nolist
  setlocal nocursorline
  setlocal nocursorcolumn
  setlocal colorcolumn=
  setlocal scrolloff=0
  setlocal nofoldenable
  setlocal textwidth=0
  setlocal nospell
  setlocal statusline=
  setlocal winfixwidth
  setlocal winfixheight
  if s:opt('slides_conceallevel', 0)
    let &l:conceallevel = s:opt('slides_conceallevel', 0)
  endif

  nnoremap <silent> <buffer> n         :call slides#next()<CR>
  nnoremap <silent> <buffer> <Space>   :call slides#next()<CR>
  nnoremap <silent> <buffer> <Right>   :call slides#next()<CR>
  nnoremap <silent> <buffer> <PageDown>:call slides#next()<CR>
  nnoremap <silent> <buffer> l         :call slides#next()<CR>
  nnoremap <silent> <buffer> N         :call slides#prev()<CR>
  nnoremap <silent> <buffer> <BS>      :call slides#prev()<CR>
  nnoremap <silent> <buffer> <Left>    :call slides#prev()<CR>
  nnoremap <silent> <buffer> <PageUp>  :call slides#prev()<CR>
  nnoremap <silent> <buffer> h         :call slides#prev()<CR>
  nnoremap <silent> <buffer> q         :call slides#quit()<CR>
  nnoremap <silent> <buffer> <Esc>     :call slides#quit()<CR>
  nnoremap <silent> <buffer> g         :call slides#goto(1)<CR>
  nnoremap <silent> <buffer> gg        :call slides#goto(1)<CR>
  nnoremap <silent> <buffer> G         :call slides#goto(slides#slide_count())<CR>
  nnoremap <silent> <buffer> r         :call slides#resize_current()<CR>
  nnoremap <silent> <buffer> s         :call slides#preview#toggle()<CR>
  nnoremap <silent> <buffer> ?         :call slides#help()<CR>

  augroup SlidesPresent
    autocmd! * <buffer>
    autocmd VimResized <buffer> call s:on_vim_resized()
    autocmd BufWipeout <buffer> call slides#quit()
  augroup END

  if s:opt('slides_colors', 1)
    call s:apply_colors()
  endif
endfunction

function! s:apply_colors() abort
  highlight! SlidesStatus ctermfg=8 ctermbg=NONE guifg=#666666 guibg=NONE
  highlight! SlidesBlank ctermbg=NONE guibg=NONE
endfunction

function! slides#help() abort
  echo 'n/l/Spacja/→  następny   N/h/BS/←  poprzedni   g/G  pierwszy/ostatni   s  podgląd   r  rozmiar   q  koniec'
endfunction

" ---------------------------------------------------------------------------
" Nawigacja
" ---------------------------------------------------------------------------

function! slides#start() abort
  if s:state.active
    call slides#quit()
  endif
  let l:slides = slides#parse_buffer(bufnr('%'))
  if empty(l:slides)
    echohl ErrorMsg
    echom 'slides.vim: brak slajdów. Oddziel je linią ~~~~'
    echohl None
    return
  endif
  let s:state.active = 1
  let s:state.slides = l:slides
  let s:state.index = 0
  let s:state.source_bufnr = bufnr('%')
  let s:state.source_winid = exists('*win_getid') ? win_getid() : 0
  only
  call s:apply_present_options()
  call s:prepare_present_buffer()
  if s:opt('slides_preview', 1)
    call slides#preview#open(s:state)
  endif
  call s:render()
  echo printf('Slides: 1/%d  n/p  q koniec | podglad: vim %s',
        \ len(s:state.slides), slides#preview#file())
endfunction

function! slides#next() abort
  if !s:state.active
    return
  endif
  if s:state.index >= len(s:state.slides) - 1
    echo 'Ostatni slajd'
    return
  endif
  let s:state.index += 1
  call s:render()
endfunction

function! slides#prev() abort
  if !s:state.active
    return
  endif
  if s:state.index <= 0
    echo 'Pierwszy slajd'
    return
  endif
  let s:state.index -= 1
  call s:render()
endfunction

function! slides#goto(n) abort
  if !s:state.active
    return
  endif
  let l:i = a:n - 1
  if l:i < 0 || l:i >= len(s:state.slides)
    echom printf('Slajd %d nie istnieje (1–%d)', a:n, len(s:state.slides))
    return
  endif
  let s:state.index = l:i
  call s:render()
endfunction

function! slides#quit() abort
  if !s:state.active
    return
  endif
  let s:state.active = 0
  let s:last_csi = [0, 0]
  let s:resizing = 0
  call slides#preview#close()
  call s:restore_options()
  augroup SlidesPresent
    autocmd!
  augroup END
  if s:state.present_bufnr > 0 && bufexists(s:state.present_bufnr)
    execute 'silent! bwipeout!' s:state.present_bufnr
  endif
  let s:state.present_bufnr = -1
  if s:state.source_bufnr > 0 && bufexists(s:state.source_bufnr)
    execute 'keepalt buffer' s:state.source_bufnr
  endif
  let s:state.slides = []
  echo 'Koniec prezentacji'
endfunction
