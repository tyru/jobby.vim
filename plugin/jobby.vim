scriptencoding utf-8

if exists('g:loaded_jobby')
    finish
endif
let g:loaded_jobby = 1

let s:save_cpo = &cpo
set cpo&vim


" TODO: Completion
"   if cmd startswith ':' { complete vim commands }
"   else                  { complete external commands }
" TODO: Allows users to determine which to invoke (<q-args>, <f-args>)
command! -nargs=+ JobbyRun call jobby#run(<q-args>, [<f-args>])
" TODO: Completion (from s:job_list)
command! -nargs=+ JobbyStop call jobby#stop(<q-args>)
command! -nargs=0 JobbyList call jobby#list()


let &cpo = s:save_cpo
unlet s:save_cpo
