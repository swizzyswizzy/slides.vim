" autoload/slides/preview.vim
" Drugie okno Vima (nie Neovim) z podglądem NASTĘPNEGO slajdu.

let s:root = expand('<sfile>:p:h:h:h')
let s:preview_vimrc = s:root . '/autoload/slides/preview.vimrc'
let s:dir = ''
let s:next_file = ''
let s:job = 0
let s:server = 'SLIDESPREV' . getpid()
let s:open = 0
let s:timer = -1
let s:fallback_buf = -1
let s:fallback_win = -1

function! slides#preview#is_open() abort
  return s:open
endfunction

function! slides#preview#file() abort
  call s:tmpdir()
  return s:next_file
endfunction

function! s:tmpdir() abort
  if !empty(get(g:, 'slides_preview_file', ''))
    let s:next_file = expand(g:slides_preview_file)
    let s:dir = fnamemodify(s:next_file, ':h')
    if !isdirectory(s:dir)
      silent! call mkdir(s:dir, 'p', 0700)
    endif
    return s:dir
  endif
  if empty(s:dir) || !isdirectory(s:dir)
    let s:dir = expand('$HOME') . '/.cache/slides.vim'
    silent! call mkdir(s:dir, 'p', 0700)
  endif
  let s:next_file = s:dir . '/next-slide.txt'
  return s:dir
endfunction

function! slides#preview#listen() abort
  call s:tmpdir()
  if !filereadable(s:next_file)
    call writefile(['(czekam na :SlidesStart)'], s:next_file)
  endif
  execute 'edit' fnameescape(s:next_file)
  setlocal autoread noswapfile nomodifiable nomodified
  setlocal laststatus=0 nonumber norelativenumber nowrap
  if exists('s:listen_timer') && s:listen_timer >= 0 && has('timers')
    call timer_stop(s:listen_timer)
  endif
  if has('timers')
    let s:listen_timer = timer_start(250, function('s:listen_tick'), {'repeat': -1})
  endif
  echo 'Podglad slajdow: ' . s:next_file
endfunction

function! s:listen_tick(...) abort
  if !bufexists(s:next_file) && bufname('%') !=# s:next_file
    return
  endif
  silent! checktime
endfunction

function! slides#preview#toggle() abort
  if s:open
    call slides#preview#close()
    echo 'Podgląd wyłączony'
  else
    call slides#preview#open({})
    echo 'Podgląd włączony'
  endif
endfunction

function! slides#preview#open(...) abort
  if s:open
    call slides#preview#update(a:0 ? a:1 : {})
    return
  endif
  call s:tmpdir()
  call slides#preview#update(a:0 ? a:1 : {})
  let l:cmd = s:build_cmd()
  if empty(l:cmd)
    echohl WarningMsg
    echom 'slides.vim: nie udało się uruchomić okna podglądu. Ustaw g:slides_preview_cmd albo zainstaluj gvim.'
    echohl None
    if get(g:, 'slides_preview_fallback_split', 0)
      call s:fallback_split()
    endif
    echom 'Podglad: w drugiej konsoli  vim ' . s:next_file . '  |  :SlidesPreviewListen'
    return
  endif
  let s:job = s:spawn(l:cmd)
  let s:open = 1
  if has('timers')
    if s:timer >= 0
      call timer_stop(s:timer)
    endif
    let s:timer = timer_start(500, function('s:place_later'))
  else
    call s:place_preview_window()
  endif
endfunction

function! s:place_later(...) abort
  call s:place_preview_window()
endfunction

function! slides#preview#update(...) abort
  call s:tmpdir()
  let l:idx = slides#current_index()
  let l:n = slides#slide_count()
  let l:next_idx = l:idx + 1
  if l:next_idx >= l:n
    let l:lines = ['', '', '  (koniec prezentacji)']
    let l:header = printf('PODGLAD  --  koniec  (%d/%d)', l:n, l:n)
    call slides#image#hide_preview()
  else
    let l:raw = slides#get_slide(l:next_idx)
    let l:header = printf('PODGLAD NASTEPNEGO  --  slajd %d/%d', l:next_idx + 1, l:n)
    let l:spec = slides#image#spec(l:raw)
    if !empty(l:spec)
      let l:path = slides#image#resolve(l:spec)
      let l:lines = ['[image]', fnamemodify(l:path, ':t'), l:path]
      call slides#image#show_preview(l:path)
    else
      let l:lines = l:raw
      call slides#image#hide_preview()
    endif
  endif
  let l:bar = repeat('-', max([strdisplaywidth(l:header), s:maxw(l:lines), 8]))
  let l:out = [l:header, l:bar, ''] + l:lines
  call writefile(l:out, s:next_file)
  call s:notify_preview()
  if s:open && s:fallback_buf > 0 && bufexists(s:fallback_buf)
    call s:refresh_fallback(l:out)
  endif
endfunction

function! s:maxw(lines) abort
  let l:w = 0
  for l:l in a:lines
    let l:w = max([l:w, strdisplaywidth(l:l)])
  endfor
  return l:w
endfunction

function! s:notify_preview() abort
  if !has('clientserver')
    return
  endif
  try
    if index(split(serverlist(), "\n"), s:server) >= 0
      silent! call remote_send(s:server, "\<C-\>\<C-N>:checktime\<CR>:silent! e!\<CR>gg")
    endif
  catch
  endtry
endfunction

function! slides#preview#close() abort
  if s:timer >= 0 && has('timers')
    call timer_stop(s:timer)
    let s:timer = -1
  endif
  if has('clientserver')
    try
      if index(split(serverlist(), "\n"), s:server) >= 0
        silent! call remote_send(s:server, "\<C-\>\<C-N>:qa!\<CR>")
      endif
    catch
    endtry
  endif
  call s:stop_job()
  if s:fallback_win > 0 && exists('*win_id2win') && win_id2win(s:fallback_win) > 0
    silent! execute win_id2win(s:fallback_win) . 'close'
  endif
  let s:open = 0
  let s:fallback_buf = -1
  let s:fallback_win = -1
endfunction

function! s:stop_job() abort
  if type(s:job) == 0 && s:job <= 0
    return
  endif
  if exists('*job_stop') && type(s:job) != 0
    try
      call job_stop(s:job, 'kill')
    catch
    endtry
  endif
  let s:job = 0
endfunction

" ---------------------------------------------------------------------------
" Uruchamianie drugiego Vima
" ---------------------------------------------------------------------------

function! s:vim_exe() abort
  if !empty(get(g:, 'slides_vim_exe', ''))
    return g:slides_vim_exe
  endif
  if !empty(v:progpath) && executable(v:progpath)
    return v:progpath
  endif
  if executable('vim')
    return 'vim'
  endif
  if executable('gvim')
    return 'gvim'
  endif
  return 'vim'
endfunction

function! s:preview_args() abort
  return [
        \ '-n',
        \ '-u', s:preview_vimrc,
        \ '-U', 'NONE',
        \ '--noplugin',
        \ '-c', 'set autoread nomodifiable',
        \ s:next_file,
        \ ]
endfunction

function! s:build_cmd() abort
  if type(get(g:, 'slides_preview_cmd', 0)) == type([]) && !empty(g:slides_preview_cmd)
    return g:slides_preview_cmd + [s:next_file]
  endif
  if type(get(g:, 'slides_preview_cmd', 0)) == type('') && !empty(g:slides_preview_cmd)
    return [&shell, &shellcmdflag, g:slides_preview_cmd . ' ' . shellescape(s:next_file)]
  endif

  let l:exe = s:vim_exe()
  let l:args = s:preview_args()
  let l:term = s:terminal_wrapper()
  if !empty(l:term)
    return l:term + [l:exe] + l:args
  endif
  if l:exe =~# 'gvim'
    return [l:exe] + l:args
  endif
  return []
endfunction

function! s:terminal_wrapper() abort
  if type(get(g:, 'slides_terminal', 0)) == type([]) && !empty(g:slides_terminal)
    return g:slides_terminal
  endif

  " Najpierw ten sam emulator, w którym stoi prezentacja.
  let l:term = tolower($TERM)
  if !empty($ALACRITTY_SOCKET) || l:term =~# 'alacritty'
    if executable('alacritty')
      return ['alacritty', '--title', 'Slides preview', '-e']
    endif
  endif
  if !empty($KITTY_WINDOW_ID) && executable('kitty')
    return ['kitty', '--title', 'Slides preview']
  endif

  let l:candidates = [
        \ ['alacritty', '--title', 'Slides preview', '-e'],
        \ ['kitty', '--title', 'Slides preview'],
        \ ['wezterm', 'start', '--'],
        \ ['gnome-terminal', '--title=Slides preview', '--'],
        \ ['konsole', '--title', 'Slides preview', '-e'],
        \ ['xfce4-terminal', '--title', 'Slides preview', '-x'],
        \ ['xterm', '-T', 'Slides preview', '-e'],
        \ ['urxvt', '-title', 'Slides preview', '-e'],
        \ ]
  for l:c in l:candidates
    if executable(l:c[0])
      return l:c
    endif
  endfor
  return []
endfunction

function! s:spawn(cmd) abort
  let l:log = s:dir . '/preview-launch.log'
  call writefile(['CMD: ' . s:join_cmd(a:cmd)], l:log)
  if exists('*job_start')
    let l:opts = {
          \ 'in_io': 'null',
          \ 'out_io': 'file',
          \ 'out_name': s:dir . '/preview-out.log',
          \ 'err_io': 'file',
          \ 'err_name': s:dir . '/preview-err.log',
          \ 'stoponexit': '',
          \ }
    let l:job = job_start(a:cmd, l:opts)
    call writefile(['JOB: ' . string(l:job), 'STATUS: ' . job_status(l:job)], l:log, 'a')
    return l:job
  endif
  call system(s:join_cmd(a:cmd) . ' >/dev/null 2>&1 &')
  return 1
endfunction

function! s:join_cmd(cmd) abort
  return join(map(copy(a:cmd), 'shellescape(v:val)'), ' ')
endfunction

" ---------------------------------------------------------------------------
" Drugi monitor (X11 + gvim --servername)
" ---------------------------------------------------------------------------

function! s:monitors() abort
  if type(get(g:, 'slides_monitors', 0)) == type([]) && !empty(g:slides_monitors)
    return g:slides_monitors
  endif
  if !executable('xrandr')
    return []
  endif
  let l:out = systemlist('xrandr --query')
  let l:mons = []
  for l:line in l:out
    let l:m = matchlist(l:line,
          \ '\v^(\S+)\s+connected(\s+primary)?\s+(\d+)x(\d+)\+(\d+)\+(\d+)')
    if empty(l:m)
      continue
    endif
    call add(l:mons, {
          \ 'name': l:m[1],
          \ 'primary': !empty(l:m[2]),
          \ 'w': str2nr(l:m[3]),
          \ 'h': str2nr(l:m[4]),
          \ 'x': str2nr(l:m[5]),
          \ 'y': str2nr(l:m[6]),
          \ })
  endfor
  return l:mons
endfunction

function! s:pick_preview_monitor(mons) abort
  if empty(a:mons)
    return {}
  endif
  for l:m in a:mons
    if !get(l:m, 'primary', 0)
      return l:m
    endif
  endfor
  let l:m = a:mons[0]
  return {
        \ 'x': l:m.x + l:m.w / 2,
        \ 'y': l:m.y,
        \ 'w': l:m.w / 2,
        \ 'h': l:m.h,
        \ }
endfunction

function! s:place_preview_window(...) abort
  let l:pos = get(g:, 'slides_preview_winpos', [])
  if len(l:pos) >= 2
    let l:x = l:pos[0]
    let l:y = l:pos[1]
  else
    let l:target = s:pick_preview_monitor(s:monitors())
    if empty(l:target)
      return
    endif
    let l:x = get(l:target, 'x', 0) + get(g:, 'slides_preview_margin', 40)
    let l:y = get(l:target, 'y', 0) + get(g:, 'slides_preview_margin', 40)
  endif

  if has('clientserver')
    try
      if index(split(serverlist(), "\n"), s:server) >= 0
        silent! call remote_send(s:server,
              \ printf("\<C-\>\<C-N>:winpos %d %d\<CR>", l:x, l:y))
      endif
    catch
    endtry
  endif

  if executable('wmctrl')
    silent! call system(printf(
          \ 'wmctrl -l | awk ''BEGIN{IGNORECASE=1} /[Ss]lides preview|[Nn]ext-slide|SLIDESPREV/ {print $1}'' | ' .
          \ 'while read id; do wmctrl -i -r "$id" -e 0,%d,%d,-1,-1; done',
          \ l:x, l:y))
  elseif executable('xdotool')
    silent! call system(printf(
          \ 'xdotool search --name "Slides preview" windowmove %%@ %d %d',
          \ l:x, l:y))
  endif
endfunction

" ---------------------------------------------------------------------------
" Fallback: split w tym samym Vimie
" ---------------------------------------------------------------------------

function! s:fallback_split() abort
  botright vnew
  let s:fallback_buf = bufnr('%')
  if exists('*win_getid')
    let s:fallback_win = win_getid()
  else
    let s:fallback_win = 0
  endif
  silent! file [slides-preview]
  setlocal buftype=nofile noswapfile nobuflisted
  setlocal nomodifiable nomodified
  setlocal nonumber norelativenumber nowrap
  setlocal statusline=\ PODGLAD\ NASTEPNEGO
  wincmd p
  let s:open = 1
  call slides#preview#update({})
endfunction

function! s:refresh_fallback(lines) abort
  if s:fallback_buf < 0 || !bufexists(s:fallback_buf)
    return
  endif
  let l:w = bufwinnr(s:fallback_buf)
  if l:w < 0
    return
  endif
  execute l:w . 'wincmd w'
  setlocal modifiable
  silent %delete _
  call setline(1, a:lines)
  setlocal nomodifiable nomodified
  wincmd p
endfunction
