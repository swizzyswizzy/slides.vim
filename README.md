# vim-slides

Wtyczka **tylko dla Vima 8+** (nie Neovim). Slajdy ze zwykłego tekstu,
prezentacja pełnoekranowa, podgląd następnego slajdu na drugim monitorze
oraz dynamiczna zmiana rozmiaru okna terminala do najszerszej linii.

Separator slajdów: linia złożona wyłącznie z `~~~~` (`\n~~~~\n`).

## Instalacja (vim-plug)

Dodaj do `.vimrc` obok pozostałych wtyczek:

```vim
call plug#begin()

Plug 'c64cosmin/harpwn'
Plug 'mbbill/undotree'
Plug 'tpope/vim-commentary'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'nathanaelkane/vim-indent-guides'
Plug 'preservim/nerdcommenter'
Plug 'rluba/jai.vim'
Plug 'sotte/presenting.vim'
Plug 'c64cosmin/vim-slides'

call plug#end()
```

Potem w Vimie:

```
:PlugInstall
```

Repozytorium na GitHubie musi nazywać się dokładnie `vim-slides`
(użytkownik `c64cosmin`). Po pierwszym wypchnięciu kodu vim-plug
ściągnie je komendą powyżej.

Jeśli repo jeszcze nie jest publiczne, możesz wskazać lokalną ścieżkę:

```vim
Plug '~/src/vim-slides'
```

albo URL:

```vim
Plug 'https://github.com/c64cosmin/vim-slides.git'
```

Po instalacji wygeneruj help:

```
:helptags ~/.vim/plugged/vim-slides/doc
:help slides
```

## Wypchnięcie do GitHuba (raz)

```bash
# na stronie github.com/new utwórz puste repo: c64cosmin/vim-slides
cd vim-slides
git init -b main
git add .
git commit -m "vim-slides: prezentacje w Vimie"
git remote add origin git@github.com:c64cosmin/vim-slides.git
git push -u origin main
```

## Szybki start

1. Otwórz plik ze slajdami, np. `example/demo.slides`.
2. `:SlidesStart` (alias `:Slides`).
3. `n` / `p` — następny / poprzedni, `s` — podgląd, `q` — koniec.

```
Tytuł

krótki tekst
~~~~
Drugi slajd
z dłuższą linią — okno się poszerzy.
~~~~
Koniec.
```

## Wymagania

- Vim 8.0+ skompilowany jako zwykły `vim` albo `gvim`
- Podgląd jako osobne okno: `gvim` z `+clientserver` (zalecane)
- Dynamiczny resize terminala: emulator rozumiejący `CSI 8 ; rows ; cols t`
- Auto-pozycja na X11: `xrandr` oraz opcjonalnie `wmctrl` / `xdotool`

Neovim jest świadomie pomijany (`plugin/slides.vim` kończy pracę przy `has('nvim')`).

## Drugi monitor

Kolejność uruchamiania podglądu:

1. `g:slides_preview_cmd` — jeśli ustawisz własną komendę
2. `gvim --servername …` (osobne okno, `winpos` na drugi ekran)
3. nowy terminal (`kitty`, `alacritty`, `xterm`, …) z `vim --servername`
4. pionowy split w bieżącym Vimie

```vim
let g:slides_preview_winpos = [1920, 40]
let g:slides_vim_exe = 'gvim'
```

## Opcje

```vim
let g:slides_separator   = '\n~~~~\n'
let g:slides_preview     = 1
let g:slides_fullscreen  = 1
let g:slides_resize_mode = 'current'   " albo 'max'
let g:slides_pad_x       = 6
let g:slides_pad_y       = 3
let g:slides_min_columns = 40
let g:slides_min_lines   = 12
```

Klawisze w trybie prezentacji: `n` `Space` `→` następny, `p` `BS` `←` poprzedni,
`g` / `G` pierwszy / ostatni, `s` podgląd, `r` rozmiar, `q` koniec.

Szczegóły: `:help slides`.
