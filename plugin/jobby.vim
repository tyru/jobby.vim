scriptencoding utf-8

if exists('g:loaded_jobby')
    finish
endif
let g:loaded_jobby = 1

if !has('patch-7.4.1393')
    echohl ErrorMsg
    echomsg 'This plugin requires Vim 7.4.1393 or higher.'
    echohl None
    finish
endif

let s:save_cpo = &cpo
set cpo&vim


" TODO: Completion
"   if cmd startswith ':' { complete vim commands }
"   else                  { complete external commands }
" TODO: Allows users to determine which to invoke (<q-args>, <f-args>)
command! -nargs=+
\   JobbyRun call jobby#run(<q-args>, [<f-args>])
command! -nargs=+ -complete=customlist,jobby#__stop_complete__
\   JobbyStop call jobby#stop(<q-args>)
command! -nargs=0
\   JobbyList call jobby#list()
command! -nargs=0
\   JobbyClean call jobby#clean()


let &cpo = s:save_cpo
unlet s:save_cpo
