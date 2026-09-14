# slides.vim

Plain-text slide deck for **Vim 8+** (not Neovim).

Slides are blocks of ordinary text split by a line of four tildes (`~~~~`).
`:SlidesStart` presents the current buffer: the terminal window resizes to the
widest line of the current slide, and a second Vim instance shows the *next*
slide (presenter view).

Existing Vim slide plugins treat the editor as a poor PowerPoint: heading-based
splits, no dual-monitor preview, no physical terminal resize, extra markup
you do not need on stage. This one does the three things that matter and
nothing else.

## Install

```vim
Plug 'swizzyswizzy/slides.vim'
```

```
:PlugInstall
:helptags ~/.vim/plugged/slides.vim/doc
```

Requires Vim 8.0+. Preview launches a second terminal (Alacritty, kitty, …)
or `gvim`. Window resize uses xterm `CSI 8 ; rows ; cols t`.

## Usage

```
Title slide
~~~~
Body slide
~~~~
End
```

```
:SlidesStart
```

| Key | Action |
|---|---|
| `n ` `→` | next |
| `Shift+ N` `←` | previous |
| `g` / `G` | first / last |
| `s` | toggle preview |
| `r` | refit window |
| `q` | quit |

Second monitor, if auto-place misses:

```vim
let g:slides_preview_winpos = [1920, 40]
```

Preview file (manual listen): `~/.cache/slides.vim/next-slide.txt`  
then `:SlidesPreviewListen` in the other Vim.

```vim
let g:slides_separator_line = '~~~~'
let g:slides_resize_mode    = 'current'   " or 'max'
let g:slides_pad_x          = 6
let g:slides_pad_y          = 3
```

`:help slides`

## Bugs

Please do not create pull requests with your code. Either open a GitHub **Issue** or write to marek`<at>`zytko.net.
Include Vim version (`vim --version`), terminal, and the exact command
that failed. Launch logs live in `~/.cache/slides.vim/`.
