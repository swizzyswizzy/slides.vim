" autoload/slides/image.vim
" Slajd file:obraz.jpg → pełny ekran w bundled view.py (GTK, potem Tk).
" view.py pisze next/prev/quit do pliku; timer w Vimie to wykonuje.

let s:job_current = 0
let s:path_current = ''
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

" <sfile> w funkcji to nazwa funkcji, nie plik. Ścieżkę bierzemy przy source.
let s:view_py = expand('<sfile>:p:h') . '/view.py'

function! s:log(msg) abort
  if !isdirectory(s:cache)
    call mkdir(s:cache, 'p', 0700)
  endif
  call writefile([strftime('%H:%M:%S') . ' ' . a:msg], s:cache . '/image.log', 'a')
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

function! slides#image#show_current(path) abort
  if empty(a:path)
    call slides#image#hide_current()
    return 'empty path'
  endif
  if !filereadable(a:path)
    call slides#image#hide_current()
    call s:log('missing file ' . a:path)
    return 'brak pliku: ' . a:path
  endif
  if !executable('python3')
    call slides#image#hide_current()
    return 'brak python3 — potrzebny do podglądu obrazu'
  endif
  let l:py = s:view_py
  if !filereadable(l:py)
    call slides#image#hide_current()
    return 'brak ' . l:py . ' (wgraj view.py obok image.vim)'
  endif
  if s:path_current ==# a:path && s:alive(s:job_current)
    return ''
  endif
  call slides#image#hide_current()
  call s:start_poll()
  let s:job_current = s:spawn(['python3', l:py, '--cmd', s:cmdfile, a:path])
  let s:path_current = a:path
  call s:log('viewer=view.py path=' . a:path)
  return ''
endfunction

function! slides#image#show_preview(...) abort
  " Jeden podglądarka: tylko bieżący slajd. Następny obraz jest etykietą w Vimie.
  return
endfunction

function! slides#image#hide_current() abort
  call s:stop_poll()
  call s:stop(s:job_current)
  let s:job_current = 0
  let s:path_current = ''
endfunction

function! slides#image#hide_preview() abort
  return
endfunction

function! slides#image#close() abort
  call slides#image#hide_current()
endfunction
