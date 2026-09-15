" autoload/slides/image.vim
" Slajd-obraz: jedna linia  file:nazwa.png
" Render: zewnętrzny podglądarka pełnoekranowa (feh / imv / mpv / nsxiv / sxiv).

let s:job_current = 0
let s:job_preview = 0
let s:path_current = ''
let s:path_preview = ''
let s:warned = 0

function! slides#image#is_slide(lines) abort
  return !empty(slides#image#spec(a:lines))
endfunction

function! slides#image#spec(lines) abort
  if type(a:lines) != type([]) || empty(a:lines)
    return ''
  endif
  let l:nonempty = []
  for l:line in a:lines
    if l:line !~# '^\s*$'
      call add(l:nonempty, l:line)
    endif
  endfor
  if len(l:nonempty) != 1
    return ''
  endif
  let l:m = matchlist(l:nonempty[0], '\v^\s*file:\s*(\S.*\S|\S)\s*$')
  if empty(l:m)
    return ''
  endif
  return l:m[1]
endfunction

function! slides#image#resolve(spec) abort
  if empty(a:spec)
    return ''
  endif
  let l:raw = expand(a:spec)
  if l:raw[0] ==# '/' || l:raw =~# '^\a:[/\\]'
    return simplify(l:raw)
  endif
  let l:root = getcwd()
  if exists('g:slides_source_dir') && !empty(g:slides_source_dir)
    let l:root = g:slides_source_dir
  endif
  return simplify(l:root . '/' . l:raw)
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

function! s:cmd_for(exe, path, fullscreen) abort
  if type(get(g:, 'slides_image_cmd', 0)) == type([]) && !empty(g:slides_image_cmd)
    return g:slides_image_cmd + [a:path]
  endif
  if a:exe ==# 'feh'
    let l:cmd = ['feh', '--auto-zoom', '--hide-pointer', '--no-menus',
          \ '--image-bg', 'black', '--title', a:fullscreen ? 'slides-current' : 'slides-preview-image']
    if a:fullscreen
      let l:cmd += ['--fullscreen']
    endif
    return l:cmd + ['--', a:path]
  endif
  if a:exe ==# 'imv'
    let l:cmd = ['imv', '--background', '1a1a1a']
    if a:fullscreen
      let l:cmd += ['-f']
    endif
    return l:cmd + [a:path]
  endif
  if a:exe ==# 'mpv'
    let l:cmd = ['mpv', '--image', '--loop-file=inf', '--no-osc',
          \ '--no-input-default-bindings', '--input-vo-keyboard=no',
          \ '--force-window=yes', '--title=' . (a:fullscreen ? 'slides-current' : 'slides-preview-image')]
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
  if exists('*job_start')
    return job_start(a:cmd, {
          \ 'in_io': 'null',
          \ 'out_io': 'null',
          \ 'err_io': 'null',
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

function! s:refocus_vim() abort
  " Obraz ma zostać on-top, klawisze wracają do Vima.
  if executable('xdotool')
    silent! call system('xdotool getactivewindow >/dev/null')
  endif
  if executable('wmctrl')
    silent! call system("wmctrl -r slides-current -b add,above")
    silent! call system("wmctrl -r slides-preview-image -b add,above")
    " aktywuj okno, z którego wystartowano prezentację
    if !empty($WINDOWID)
      silent! call system('wmctrl -i -a ' . $WINDOWID)
    endif
  elseif executable('xdotool')
    if !empty($WINDOWID)
      silent! call system('xdotool windowactivate --sync ' . $WINDOWID)
    endif
  endif
endfunction

function! s:place_preview_image() abort
  let l:pos = get(g:, 'slides_preview_winpos', [])
  if len(l:pos) < 2
    return
  endif
  if executable('wmctrl')
    silent! call system(printf(
          \ 'wmctrl -r slides-preview-image -e 0,%d,%d,-1,-1',
          \ l:pos[0], l:pos[1]))
  elseif executable('xdotool')
    silent! call system(printf(
          \ 'xdotool search --name slides-preview-image windowmove %%@ %d %d',
          \ l:pos[0], l:pos[1]))
  endif
endfunction

function! slides#image#show_current(path) abort
  if empty(a:path)
    call slides#image#hide_current()
    return
  endif
  if !filereadable(a:path)
    call slides#image#hide_current()
    echohl ErrorMsg
    echom 'slides.vim: nie ma pliku ' . a:path
    echohl None
    return
  endif
  if s:path_current ==# a:path && s:alive(s:job_current)
    return
  endif
  call slides#image#hide_current()
  let l:exe = slides#image#viewer()
  if !executable(l:exe)
    if !s:warned
      let s:warned = 1
      echohl ErrorMsg
      echom 'slides.vim: brak podglądarki obrazów. Zainstaluj feh (albo imv / mpv / nsxiv).'
      echohl None
    endif
    return
  endif
  let s:job_current = s:spawn(s:cmd_for(l:exe, a:path, 1))
  let s:path_current = a:path
  if has('timers')
    call timer_start(250, {-> s:refocus_vim()})
  else
    call s:refocus_vim()
  endif
endfunction

function! slides#image#show_preview(path) abort
  if empty(a:path) || !filereadable(a:path)
    call slides#image#hide_preview()
    return
  endif
  if s:path_preview ==# a:path && s:alive(s:job_preview)
    return
  endif
  call slides#image#hide_preview()
  let l:exe = slides#image#viewer()
  if !executable(l:exe)
    return
  endif
  let s:job_preview = s:spawn(s:cmd_for(l:exe, a:path, 0))
  let s:path_preview = a:path
  if has('timers')
    call timer_start(350, {-> s:place_preview_image()})
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
