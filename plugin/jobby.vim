scriptencoding utf-8

if exists('g:loaded_jobby')
    finish
endif
let g:loaded_jobby = 1

let s:save_cpo = &cpo
set cpo&vim


" TODO
" command! JobbyRun ...
" command! JobbyStop ...
" command! JobbyList ...


let &cpo = s:save_cpo
unlet s:save_cpo
