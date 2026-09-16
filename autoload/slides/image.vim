" autoload/slides/image.vim
" Slajd-obraz: linia file:nazwa.png → pełny ekran w feh/imv/mpv/nsxiv/sxiv.

let s:job_current = 0
let s:job_preview = 0
let s:path_current = ''
let s:path_preview = ''

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
  for l:exe in ['feh', 'imv', 'mpv', 'nsxiv', 'sxiv']
    if executable(l:exe)
      return l:exe
    endif
  endfor
  return 'feh'
endfunction

function! s:log(msg) abort
  let l:dir = expand('$HOME') . '/.cache/slides.vim'
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p', 0700)
  endif
  call writefile([strftime('%H:%M:%S') . ' ' . a:msg], l:dir . '/image.log', 'a')
endfunction

function! s:cmd_for(exe, path, fullscreen) abort
  if type(get(g:, 'slides_image_cmd', 0)) == type([]) && !empty(g:slides_image_cmd)
    return g:slides_image_cmd + [a:path]
  endif
  if a:exe ==# 'feh'
    let l:cmd = ['feh', '--auto-zoom', '--hide-pointer', '--no-menus',
          \ '--image-bg', 'black',
          \ '--title', a:fullscreen ? 'slides-current' : 'slides-preview-image']
    if a:fullscreen
      let l:cmd += ['--fullscreen']
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
  if a:exe ==# 'mpv'
    let l:cmd = ['mpv', '--image', '--loop-file=inf', '--no-osc',
          \ '--no-input-default-bindings', '--input-vo-keyboard=no',
          \ '--force-window=yes',
          \ '--title=' . (a:fullscreen ? 'slides-current' : 'slides-preview-image')]
    if a:fullscreen
      let l:cmd += ['--fs', '--ontop']
    endif
    return l:cmd + ['--', a:path]
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

function! s:spawn(cmd) abort
  call s:log('spawn ' . join(a:cmd, ' '))
  if exists('*job_start')
    return job_start(a:cmd, {
          \ 'in_io': 'null',
          \ 'out_io': 'file',
          \ 'out_name': expand('$HOME') . '/.cache/slides.vim/image-out.log',
          \ 'err_io': 'file',
          \ 'err_name': expand('$HOME') . '/.cache/slides.vim/image-err.log',
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

function! s:raise_image(...) abort
  " Obraz NA WIERZCHU. Vima nie podnosimy — inaczej zasłania feh.
  if executable('wmctrl')
    silent! call system('wmctrl -r slides-current -b add,above,fullscreen')
    silent! call system('wmctrl -a slides-current')
  endif
  if executable('xdotool') && !empty($WINDOWID)
    " focus klawiatury na Vim, bez podnoszenia okna
    silent! call system('xdotool windowfocus ' . $WINDOWID)
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
  let l:cmd = s:cmd_for(l:exe, a:path, 1)
  let s:job_current = s:spawn(l:cmd)
  let s:path_current = a:path
  call s:log('viewer=' . l:exe . ' job=' . string(s:job_current) . ' path=' . a:path)
  if has('timers')
    call timer_start(200, function('s:raise_image'))
    call timer_start(600, function('s:raise_image'))
  else
    call s:raise_image()
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
