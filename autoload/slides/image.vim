" autoload/slides/image.vim
" Obraz na wierzchu; n/N/q działają nawet gdy fokus ma podglądarka.
" Podglądarka pisze komendę do pliku, timer w Vimie ją wykonuje.

let s:job_current = 0
let s:job_preview = 0
let s:path_current = ''
let s:path_preview = ''
let s:poll_timer = -1
let s:cache = expand('$HOME') . '/.cache/slides.vim'
let s:cmdfile = s:cache . '/cmd'

function! slides#image#is_slide(lines) abort
  return !empty(slides#image#spec(a:lines))
endfunction

function! slides#image#spec(lines) abort
  if type(a:lines) != type([])
    return ''
  endif
  for l:line in a:lines
    let l:line = substitute(l:line, '^\s\+', '', '')
    let l:line = substitute(l:line, '\s\+$', '', '')
    if l:line =~? '^file:'
      return substitute(l:line, '^file:\s*', '', '')
    endif
  endfor
  return ''
endfunction

function! slides#image#resolve(spec) abort
  if empty(a:spec)
    return ''
  endif
  let l:raw = expand(a:spec)
  if l:raw[0] ==# '/' || l:raw =~# '^\a:[/\\]'
    return simplify(l:raw)
  endif
  let l:dirs = []
  if exists('g:slides_source_dir') && !empty(g:slides_source_dir)
    call add(l:dirs, g:slides_source_dir)
  endif
  call add(l:dirs, getcwd())
  for l:dir in l:dirs
    let l:try = simplify(l:dir . '/' . l:raw)
    if filereadable(l:try)
      return l:try
    endif
  endfor
  if exists('g:slides_source_dir') && !empty(g:slides_source_dir)
    return simplify(g:slides_source_dir . '/' . l:raw)
  endif
  return simplify(getcwd() . '/' . l:raw)
endfunction

function! slides#image#source_dir(bufnr) abort
  let l:name = bufname(a:bufnr)
  if empty(l:name)
    return getcwd()
  endif
  return fnamemodify(fnamemodify(l:name, ':p'), ':h')
endfunction

function! slides#image#viewer() abort
  if !empty(get(g:, 'slides_image_viewer', ''))
    return g:slides_image_viewer
  endif
  " mpv: izolowany input.conf + --ontop; feh: działa u Ciebie, klawisze przez --action
  for l:exe in ['mpv', 'feh', 'imv', 'nsxiv', 'sxiv']
    if executable(l:exe)
      return l:exe
    endif
  endfor
  return 'feh'
endfunction

function! s:log(msg) abort
  if !isdirectory(s:cache)
    call mkdir(s:cache, 'p', 0700)
  endif
  call writefile([strftime('%H:%M:%S') . ' ' . a:msg], s:cache . '/image.log', 'a')
endfunction

function! s:write_cmd(name) abort
  if !isdirectory(s:cache)
    call mkdir(s:cache, 'p', 0700)
  endif
  call writefile([a:name], s:cmdfile)
endfunction

function! s:feh_home() abort
  let l:home = s:cache . '/feh-home'
  call mkdir(l:home . '/.config/feh', 'p', 0700)
  " n/Space/Right → action_1 (next), N/Left → action_2 (prev), q/Esc → action_3 (quit)
  call writefile([
        \ 'action_1 n space Right',
        \ 'action_2 N Left BackSpace',
        \ 'action_3 q Escape',
        \ ], l:home . '/.config/feh/keys')
  return l:home
endfunction

function! s:mpv_conf() abort
  let l:conf = s:cache . '/mpv-input.conf'
  let l:sh = 'echo %s > ' . shellescape(s:cmdfile)
  call writefile([
        \ 'n     run "/bin/sh" "-c" "echo next > ' . s:cmdfile . '"',
        \ 'SPACE run "/bin/sh" "-c" "echo next > ' . s:cmdfile . '"',
        \ 'RIGHT run "/bin/sh" "-c" "echo next > ' . s:cmdfile . '"',
        \ 'N     run "/bin/sh" "-c" "echo prev > ' . s:cmdfile . '"',
        \ 'LEFT  run "/bin/sh" "-c" "echo prev > ' . s:cmdfile . '"',
        \ 'q     run "/bin/sh" "-c" "echo quit > ' . s:cmdfile . '"',
        \ 'ESC   run "/bin/sh" "-c" "echo quit > ' . s:cmdfile . '"',
        \ ], l:conf)
  return l:conf
endfunction

function! s:cmd_for(exe, path, fullscreen) abort
  if type(get(g:, 'slides_image_cmd', 0)) == type([]) && !empty(g:slides_image_cmd)
    return g:slides_image_cmd + [a:path]
  endif
  if a:exe ==# 'feh'
    let l:act = 'printf \%s > ' . shellescape(s:cmdfile)
    let l:cmd = ['env', 'HOME=' . s:feh_home(),
          \ 'feh', '--auto-zoom', '--hide-pointer', '--no-menus',
          \ '--image-bg', 'black',
          \ '--title', a:fullscreen ? 'slides-current' : 'slides-preview-image',
          \ '--action1', 'printf next > ' . s:cmdfile,
          \ '--action2', 'printf prev > ' . s:cmdfile,
          \ '--action3', 'printf quit > ' . s:cmdfile]
    if a:fullscreen
      let l:cmd += ['--fullscreen']
    endif
    return l:cmd + ['--', a:path]
  endif
  if a:exe ==# 'mpv'
    let l:cmd = ['mpv', '--image', '--loop-file=inf', '--no-osc',
          \ '--input-conf=' . s:mpv_conf(),
          \ '--no-input-default-bindings',
          \ '--force-window=yes',
          \ '--title=' . (a:fullscreen ? 'slides-current' : 'slides-preview-image')]
    if a:fullscreen
      let l:cmd += ['--fs', '--ontop']
      if s:mpv_has_focus_on()
        let l:cmd += ['--focus-on=never']
      endif
    endif
    return l:cmd + ['--', a:path]
  endif
  if a:exe ==# 'imv'
    let l:cmd = ['imv']
    if a:fullscreen
      let l:cmd += ['-f']
    endif
    return l:cmd + [a:path]
  endif
  if a:exe ==# 'nsxiv' || a:exe ==# 'sxiv'
    let l:cmd = [a:exe, '-b']
    if a:fullscreen
      let l:cmd += ['-f']
    endif
    return l:cmd + ['--', a:path]
  endif
  return [a:exe, a:path]
endfunction

function! s:mpv_has_focus_on() abort
  if !executable('mpv')
    return 0
  endif
  let l:h = system('mpv --list-options 2>/dev/null | grep -c focus-on')
  return l:h =~# '^[1-9]'
endfunction

function! s:spawn(cmd) abort
  call s:log('spawn ' . join(a:cmd, ' '))
  if exists('*job_start')
    return job_start(a:cmd, {
          \ 'in_io': 'null',
          \ 'out_io': 'file',
          \ 'out_name': s:cache . '/image-out.log',
          \ 'err_io': 'file',
          \ 'err_name': s:cache . '/image-err.log',
          \ 'stoponexit': 'term',
          \ })
  endif
  call system(join(map(copy(a:cmd), 'shellescape(v:val)'), ' ') . ' >/dev/null 2>&1 &')
  return 1
endfunction

function! s:stop(job) abort
  if type(a:job) == 0 && a:job <= 0
    return
  endif
  if exists('*job_stop') && type(a:job) != 0
    try
      call job_stop(a:job, 'kill')
    catch
    endtry
  endif
endfunction

function! s:alive(job) abort
  if type(a:job) == 0
    return a:job > 0
  endif
  if exists('*job_status')
    return job_status(a:job) ==# 'run'
  endif
  return 1
endfunction

function! s:start_poll() abort
  if !isdirectory(s:cache)
    call mkdir(s:cache, 'p', 0700)
  endif
  if filereadable(s:cmdfile)
    call delete(s:cmdfile)
  endif
  if s:poll_timer >= 0 && has('timers')
    call timer_stop(s:poll_timer)
  endif
  if has('timers')
    let s:poll_timer = timer_start(70, function('s:poll_cmd'), {'repeat': -1})
  endif
endfunction

function! s:stop_poll() abort
  if s:poll_timer >= 0 && has('timers')
    call timer_stop(s:poll_timer)
    let s:poll_timer = -1
  endif
  if filereadable(s:cmdfile)
    call delete(s:cmdfile)
  endif
endfunction

function! s:poll_cmd(...) abort
  if !filereadable(s:cmdfile)
    return
  endif
  let l:lines = readfile(s:cmdfile)
  call delete(s:cmdfile)
  if empty(l:lines)
    return
  endif
  let l:cmd = substitute(l:lines[0], '\s\+', '', 'g')
  call s:log('cmd ' . l:cmd)
  if l:cmd ==# 'next'
    call slides#next()
  elseif l:cmd ==# 'prev'
    call slides#prev()
  elseif l:cmd ==# 'quit'
    call slides#quit()
  endif
endfunction

function! s:raise_image(...) abort
  " Tylko always-on-top — NIE aktywujemy okna feh (to kradnie klawisze).
  if executable('wmctrl')
    silent! call system('wmctrl -r slides-current -b add,above')
  endif
endfunction

function! s:place_preview_image(...) abort
  let l:pos = get(g:, 'slides_preview_winpos', [])
  if len(l:pos) < 2
    return
  endif
  if executable('wmctrl')
    silent! call system(printf(
          \ 'wmctrl -r slides-preview-image -e 0,%d,%d,-1,-1',
          \ l:pos[0], l:pos[1]))
  endif
endfunction

function! slides#image#show_current(path) abort
  if empty(a:path)
    call slides#image#hide_current()
    return 'empty path'
  endif
  let l:exe = slides#image#viewer()
  if !filereadable(a:path)
    call slides#image#hide_current()
    call s:log('missing file ' . a:path)
    return 'brak pliku: ' . a:path
  endif
  if !executable(l:exe)
    call slides#image#hide_current()
    call s:log('missing viewer ' . l:exe)
    return 'brak programu ' . l:exe . ' — zainstaluj: sudo apt install feh'
  endif
  if s:path_current ==# a:path && s:alive(s:job_current)
    return ''
  endif
  call slides#image#hide_current()
  call s:start_poll()
  let s:job_current = s:spawn(s:cmd_for(l:exe, a:path, 1))
  let s:path_current = a:path
  call s:log('viewer=' . l:exe . ' path=' . a:path)
  if has('timers')
    call timer_start(200, function('s:raise_image'))
  endif
  return ''
endfunction

function! slides#image#show_preview(path) abort
  if empty(a:path) || !filereadable(a:path)
    call slides#image#hide_preview()
    return
  endif
  if s:path_preview ==# a:path && s:alive(s:job_preview)
    return
  endif
  let l:exe = slides#image#viewer()
  if !executable(l:exe)
    return
  endif
  call slides#image#hide_preview()
  let s:job_preview = s:spawn(s:cmd_for(l:exe, a:path, 0))
  let s:path_preview = a:path
  if has('timers')
    call timer_start(400, function('s:place_preview_image'))
  endif
endfunction

function! slides#image#hide_current() abort
  call s:stop_poll()
  call s:stop(s:job_current)
  let s:job_current = 0
  let s:path_current = ''
endfunction

function! slides#image#hide_preview() abort
  call s:stop(s:job_preview)
  let s:job_preview = 0
  let s:path_preview = ''
endfunction

function! slides#image#close() abort
  call slides#image#hide_current()
  call slides#image#hide_preview()
endfunction
