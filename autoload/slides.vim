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
      \ 'fs_on': 0,
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
    if s:opt('slides_fullscreen', 1)
      " Pełny ekran WM — CSI 8 t zdejmuje fullscreen i odsłania pasek.
      return [l:cols, l:rows]
    endif
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

function! s:wm_id() abort
  if !empty($WINDOWID) && $WINDOWID =~# '^\d\+$'
    return $WINDOWID
  endif
  if executable('wmctrl')
    let l:pid = getpid()
    let l:out = system('wmctrl -lp 2>/dev/null')
    for l:line in split(l:out, '\n')
      let l:f = split(l:line)
      if len(l:f) >= 3 && l:f[2] ==# string(l:pid)
        return l:f[0]
      endif
    endfor
  endif
  if executable('xdotool')
    let l:id = substitute(system('xdotool getactivewindow 2>/dev/null'), '\n', '', 'g')
    if l:id =~# '^\d\+$'
      return l:id
    endif
  endif
  return ''
endfunction

function! s:fs_log(msg) abort
  let l:dir = expand('$HOME') . '/.cache/slides.vim'
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p', 0700)
  endif
  call writefile([strftime('%H:%M:%S') . ' ' . a:msg], l:dir . '/fullscreen.log', 'a')
endfunction

function! s:alacritty_msg(...) abort
  if !executable('alacritty') || empty($ALACRITTY_SOCKET)
    return 'no-socket'
  endif
  let l:cmd = ['alacritty', 'msg', '--socket', $ALACRITTY_SOCKET] + a:000
  let l:out = system(join(map(copy(l:cmd), 'shellescape(v:val)'), ' '))
  call s:fs_log(join(l:cmd, ' ') . ' => ' . substitute(l:out, '\n', ' ', 'g'))
  return l:out
endfunction

function! s:wm_fullscreen(on) abort
  let l:way = ($XDG_SESSION_TYPE ==# 'wayland') || ($ALACRITTY_SOCKET =~# 'wayland')
  let l:awid = !empty($ALACRITTY_WINDOW_ID) ? $ALACRITTY_WINDOW_ID : $WINDOWID
  call s:fs_log((a:on ? 'ON' : 'OFF') . ' wayland=' . l:way
        \ . ' ALACRITTY_WINDOW_ID=' . $ALACRITTY_WINDOW_ID
        \ . ' sock=' . $ALACRITTY_SOCKET
        \ . ' desktop=' . $XDG_CURRENT_DESKTOP)

  " 1. Alacritty IPC — jedyne, co działa na Waylandzie bez kompozytora.
  if !empty($ALACRITTY_SOCKET) && executable('alacritty')
    let l:dec = a:on ? 'None' : 'Full'
    let l:mode = a:on ? 'Fullscreen' : 'Windowed'
    call s:alacritty_msg('config', '-w', l:awid, 'window.decorations="' . l:dec . '"')
    call s:alacritty_msg('config', '-w', l:awid, 'window.startup_mode="' . l:mode . '"')
    call s:alacritty_msg('config', '-w', l:awid, 'window.padding.x=0')
    call s:alacritty_msg('config', '-w', l:awid, 'window.padding.y=0')
    if !a:on
      call s:alacritty_msg('config', '--reset')
    endif
  endif

  " 2. Kompozytor Wayland
  if executable('hyprctl')
    call s:fs_log(system(a:on ? 'hyprctl dispatch fullscreen 1' : 'hyprctl dispatch fullscreen 0'))
  endif
  if executable('swaymsg')
    call s:fs_log(system(a:on ? 'swaymsg fullscreen enable' : 'swaymsg fullscreen disable'))
  endif
  if executable('niri')
    call s:fs_log(system('niri msg action fullscreen-window 2>&1'))
  endif
  if executable('riverctl')
    call s:fs_log(system(a:on ? 'riverctl set-fullscreen' : 'riverctl unset-fullscreen'))
  endif

  " 3. X11 (jeśli sesja jest mieszana)
  if !l:way
    let l:id = s:wm_id()
    let l:flag = a:on ? 'add' : 'remove'
    if executable('wmctrl')
      if !empty(l:id)
        silent! call system('wmctrl -i -r ' . l:id . ' -b ' . l:flag . ',fullscreen')
      endif
      silent! call system('wmctrl -r :ACTIVE: -b ' . l:flag . ',fullscreen')
    endif
    if executable('xdotool')
      let l:op = a:on ? 'add' : 'remove'
      silent! call system('xdotool getactivewindow windowstate --' . l:op . ' FULLSCREEN')
    endif
  endif

endfunction

function! s:send_f11() abort
  " Alacritty na Waylandzie honoruje tylko własne ToggleFullscreen (F11).
  if executable('wtype')
    call s:fs_log('wtype F11 => ' . system('wtype -k F11 2>&1'))
    return 1
  endif
  if executable('ydotool')
    call s:fs_log('ydotool F11 => ' . system('ydotool key 87:1 87:0 2>&1'))
    return 1
  endif
  if executable('dotool')
    call s:fs_log('dotool F11 => ' . system('printf "key F11\n" | dotool 2>&1'))
    return 1
  endif
  if executable('xdotool')
    call s:fs_log('xdotool F11 => ' . system('xdotool key --clearmodifiers F11 2>&1'))
    return 1
  endif
  call s:fs_log('brak wtype/ydotool/dotool/xdotool — nie mogę wcisnąć F11')
  return 0
endfunction

function! s:spawn_alacritty_fs() abort
  if empty($ALACRITTY_SOCKET) || !executable('alacritty')
    return 0
  endif
  let l:file = expand('%:p')
  if empty(l:file) || !filereadable(l:file)
    return 0
  endif
  let l:vim = empty(v:progpath) ? 'vim' : v:progpath
  let l:cmd = [
        \ 'alacritty', 'msg', '--socket', $ALACRITTY_SOCKET,
        \ 'create-window',
        \ '--working-directory', getcwd(),
        \ '-T', 'slides',
        \ '-o', 'window.startup_mode="Fullscreen"',
        \ '-o', 'window.decorations="None"',
        \ '-e', l:vim,
        \ '-n', '-R',
        \ '--cmd', 'set noswapfile shortmess+=A',
        \ '-c', 'let g:slides_in_fs_window=1',
        \ '-c', 'SlidesStart',
        \ l:file,
        \ ]
  call s:fs_log('spawn ' . join(l:cmd, ' '))
  if exists('*job_start')
    call job_start(l:cmd, {'in_io': 'null', 'out_io': 'null', 'err_io': 'null'})
  else
    call system(join(map(copy(l:cmd), 'shellescape(v:val)'), ' ') . ' &')
  endif
  return 1
endfunction

function! s:awid() abort
  return !empty($ALACRITTY_WINDOW_ID) ? $ALACRITTY_WINDOW_ID : '-1'
endfunction

function! s:set_font(size) abort
  let l:n = a:size
  if l:n < 6.0
    let l:n = 6.0
  endif
  if l:n > 64.0
    let l:n = 64.0
  endif
  if abs(l:n - get(s:state, 'font_now', 0)) < 0.15
    return
  endif
  let s:state.font_now = l:n
  let l:opt = printf('font.size=%.1f', l:n)
  " -w -1 = wszystkie okna tego procesu Alacritty (pewniejsze niż WINDOW_ID).
  call s:alacritty_msg('config', '-w', '-1', l:opt)
  call s:alacritty_msg('config', l:opt)
endfunction

function! s:capture_native() abort
  if &columns < 20 || &lines < 8
    return
  endif
  if get(s:state, 'nat_cols', 0) >= 20
    return
  endif
  let s:state.nat_cols = &columns
  let s:state.nat_lines = &lines
  let s:state.base_font = s:opt('slides_font_size', 11.0)
  call s:fs_log(printf('native %dx%d font=%.1f sock=%s', s:state.nat_cols, s:state.nat_lines, s:state.base_font, $ALACRITTY_SOCKET))
endfunction

function! s:fit_font(slide) abort
  if !s:opt('slides_scale_font', 1)
    return
  endif
  if empty($ALACRITTY_SOCKET) || !executable('alacritty')
    call s:fs_log('fit skip: no alacritty socket')
    return
  endif
  if !empty(slides#image#spec(a:slide))
    return
  endif
  call s:capture_native()
  if get(s:state, 'nat_cols', 0) < 20
    call s:fs_log('fit skip: no native geometry')
    return
  endif
  let l:need_c = max([s:max_width(a:slide) + 2 * s:opt('slides_pad_x', 1), 8])
  let l:need_r = max([len(a:slide) + 2 * s:opt('slides_pad_y', 1) + 2, 4])
  let l:sw = (s:state.nat_cols * 1.0) / l:need_c
  let l:sh = (s:state.nat_lines * 1.0) / l:need_r
  let l:scale = l:sw < l:sh ? l:sw : l:sh
  let l:scale = l:scale * s:opt('slides_scale_fill', 0.96)
  if l:scale < 0.8
    let l:scale = 0.8
  endif
  if l:scale > 8.0
    let l:scale = 8.0
  endif
  let l:new = get(s:state, 'base_font', 11.0) * l:scale
  call s:fs_log(printf('fit need=%dx%d nat=%dx%d scale=%.2f font=%.1f', l:need_c, l:need_r, s:state.nat_cols, s:state.nat_lines, l:scale, l:new))
  call s:set_font(l:new)
endfunction

function! s:csi_fullscreen(on) abort
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
  endif
  if !a:on && get(g:, 'slides_in_fs_window', 0) && executable('alacritty') && !empty($ALACRITTY_SOCKET)
    call s:alacritty_msg('config', '--reset')
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
  if !s:state.active || s:resizing
    return
  endif
  if get(g:, 'slides_in_fs_window', 0) && get(s:state, 'nat_cols', 0) < 20
    call s:capture_native()
  endif
  let l:slide = slides#get_slide(s:state.index)
  if !empty(slides#image#spec(l:slide))
    return
  endif
  call s:paint(&columns, &lines)
endfunction

" ---------------------------------------------------------------------------
" Render slajdu
" ---------------------------------------------------------------------------

function! s:center_lines(lines, width, height) abort
  let l:pad_x = s:opt('slides_pad_x', 1)
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
  let l:spec = slides#image#spec(l:slide)
  if !empty(l:spec)
    let g:slides_source_dir = slides#image#source_dir(s:state.source_bufnr)
    let l:path = slides#image#resolve(l:spec)
    let l:err = slides#image#show_current(l:path)
    if empty(l:err)
      let l:label = ['[image]', fnamemodify(l:path, ':t')]
    else
      let l:label = ['[image error]', l:err]
      echohl ErrorMsg
      echom 'slides.vim: ' . l:err
      echohl None
    endif
    let [l:cols, l:rows] = slides#fit_slide(l:label)
    call s:paint_lines(l:label, max([l:cols, &columns]), max([l:rows, &lines]))
  else
    call slides#image#hide_current()
    let [l:cols, l:rows] = slides#fit_slide(l:slide)
    call s:paint_lines(l:slide, max([l:cols, &columns]), max([l:rows, &lines]))
  endif
  call slides#preview#update(s:state)
  call s:fit_font(l:slide)
endfunction

function! s:paint(cols, rows) abort
  if !s:state.active || s:state.present_bufnr < 0
    return
  endif
  call s:paint_lines(slides#get_slide(s:state.index), a:cols, a:rows)
endfunction

function! s:paint_lines(slide, cols, rows) abort
  if !s:state.active || s:state.present_bufnr < 0
    return
  endif
  let l:cols = max([a:cols, 1])
  let l:rows = max([a:rows, 1])
  let l:body = s:center_lines(a:slide, l:cols, l:rows - 1)

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

  if s:opt('slides_fullscreen', 1)
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
  nnoremap <silent> <buffer> <F11>     :call slides#fullscreen(1)<CR>
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

function! slides#fullscreen(...) abort
  let l:on = a:0 ? !!a:1 : 1
  call s:csi_fullscreen(l:on)
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
  if s:opt('slides_fullscreen', 1) && !get(g:, 'slides_in_fs_window', 0)
    if s:spawn_alacritty_fs()
      return
    endif
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
  let g:slides_source_dir = slides#image#source_dir(s:state.source_bufnr)
  let s:state.source_winid = exists('*win_getid') ? win_getid() : 0
  let l:more = &more
  set nomore
  silent! only
  call s:apply_present_options()
  call s:prepare_present_buffer()
  if s:opt('slides_preview', 1)
    silent! call slides#preview#open(s:state)
  endif
  let s:state.nat_cols = 0
  let s:state.nat_lines = 0
  let s:state.font_now = 0
  call s:render()
  let &more = l:more
  redraw!
  if !empty($ALACRITTY_SOCKET)
    call s:set_font(s:opt('slides_font_size', 11.0))
    if has('timers')
      call timer_start(200, function('s:fit_later'))
      call timer_start(600, function('s:fit_later'))
    else
      call s:fit_later()
    endif
  endif
endfunction

function! s:fit_later(...) abort
  if !s:state.active
    return
  endif
  call s:capture_native()
  call s:fit_font(slides#get_slide(s:state.index))
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
  call slides#image#close()
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
  let s:state.fitted_index = -1
  if get(g:, 'slides_in_fs_window', 0)
    silent! qa!
  endif
endfunction
