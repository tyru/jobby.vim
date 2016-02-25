scriptencoding utf-8
let s:save_cpo = &cpo
set cpo&vim

let g:jobby#list_buf_open_cmd =
\   get(g:, 'jobby#list_buf_open_cmd', 'botright 5new')
let g:jobby#list_auto_preview =
\   get(g:, 'jobby#list_auto_preview', 1)


" @throws
function! jobby#run(cmdline, args) abort
    call s:job_inc_postpone_cb()
    try
        call s:do_run(a:cmdline, a:args)
    finally
        call s:job_dec_postpone_cb()
        call s:job_handle_postpone_cb()
    endtry
endfunction

function! s:do_run(cmdline, args) abort
    if a:cmdline[0] ==# ':'
        " TODO: Run Ex command in another Vim.
        " let job = job_start(...)
        throw 'not implemented yet'
    else
        " Run external command.
        let args = ['/bin/sh', '-c', a:cmdline . ' </dev/null >/dev/null']
        let job = job_start(args)
        " let job = job_start(a:cmdline, {"in-io": "null", "out-io": "null"})
    endif
    if job_status(job) ==# 'fail'
        echom '(jobby) Run(failure): ' . a:cmdline
        return
    endif
    call job_setoptions(job, {
    \   'exit-cb': 'jobby#__exit_cb__',
    \   'stoponexit': 'kill'
    \})
    " Add spawned job to job list.
    call s:job_add(job, a:cmdline)
    " Open :JobbyList buffer.
    if g:jobby#list_auto_preview
        JobbyList
    endif
    " Message
    echom '(jobby) Run(success): ' . a:cmdline
endfunction

function! jobby#__exit_cb__(job, _exitcode, ...) abort
    if !get(a:000, 0, 0)
        " Set endtime if this callback is not postponed (a:1 != 1).
        call s:job_set(a:job, 'endtime', reltime())
    endif
    if s:job_enabled_postpone_cb()
        call s:job_postpone('jobby#__exit_cb__', [a:job, a:_exitcode, 1])
        return
    endif
    call s:job_inc_postpone_cb()
    try
        " Close :JobbyList buffer if no running jobs.
        if g:jobby#list_auto_preview
            call s:try_to_close_jobby_buffer()
        endif
        " Output 'Done' message with command-line string.
        let ctx = s:job_foreach('s:get_cmdline_by_job', {'job': a:job})
        if has_key(ctx, 'cmdline')
            redraw
            echo '(jobby) Done: ' . ctx.cmdline
        endif
    finally
        call s:job_dec_postpone_cb()
        call s:job_handle_postpone_cb()
    endtry
endfunction

function! s:try_to_close_jobby_buffer() abort
    let [jobby_winnr, jobby_bufnr] = s:find_jobby_window()
    if jobby_winnr ># 0
        " Temporarily set window variable to mark previous window.
        let w:jobby_prev_window = 1
        try
            execute jobby_winnr 'wincmd w'
            let job = s:get_job_by_expr(
            \   'job_status(v:val.job) !~# ' . string('\v^(dead|fail)$')
            \)
            " Really exists jobby buffer here?
            if job is v:null && bufexists(jobby_bufnr)
                close
            endif
        finally
            " Switch back to previous window.
            for winnr in range(1, tabpagewinnr(tabpagenr(), '$'))
                if getwinvar(winnr, 'jobby_prev_window', v:null) isnot v:null
                    execute winnr 'wincmd w'
                    unlet w:jobby_prev_window
                endif
            endfor
        endtry
    endif
endfunction

function! s:get_cmdline_by_job(jobdict, ctx) abort
    if a:jobdict.job ==# a:ctx.job
        let a:ctx.cmdline = a:jobdict.cmdline
        call s:job_foreach_break()
    endif
endfunction

" @throws
function! jobby#stop(cmdline) abort
    call s:job_inc_postpone_cb()
    try
        call s:do_stop(a:cmdline)
    finally
        call s:job_dec_postpone_cb()
        call s:job_handle_postpone_cb()
    endtry
endfunction

function! s:do_stop(cmdline) abort
    if a:cmdline =~# '^[0-9]\+$'
        " Job ID
        let job = s:get_job_by_jobid(a:cmdline + 0)
        if job is v:null
            echohl ErrorMsg
            echomsg '(jobby) :JobbyStop could not find a correspond job.'
            echohl None
            return
        endif
        if s:stop_forcefully(job)
            echom '(jobby) Stop(success): ' . a:cmdline
        else
            echom '(jobby) Stop(failure): ' . a:cmdline
        endif
    else
        " TODO: Find matching jobs from job list.
        throw 'not implemented yet'
    endif
endfunction

" @throws
function! s:stop_forcefully(job) abort
    let start = reltime()
    let maxtimeSec = 5
    let waittime = 50
    let sleepcmd = 'sleep %sm'

    " Stop job.
    call job_stop(a:job, 'term')
    execute printf(sleepcmd, waittime)
    while job_status(a:job)
        let waittime = waittime * 2
        let duraSec = matchstr(reltime(start, reltime()), '\d\+')
        if duraSec >= maxtimeSec
            return 0
        endif
    endwhile

    " Remove job from job list.
    call s:job_remove(a:job)
    return 1
endfunction

function! jobby#list() abort
    call s:job_inc_postpone_cb()
    try
        call s:do_list()
    finally
        call s:job_dec_postpone_cb()
        call s:job_handle_postpone_cb()
    endtry
endfunction

function! s:do_list() abort
    let jobby_winnr = s:find_jobby_window()[0]
    if jobby_winnr > 0
        " Jump to the existing window.
        execute jobby_winnr 'wincmd w'
    else
        " Open a new jobby buffer & window.
        try
            execute g:jobby#list_buf_open_cmd
        catch
            echohl ErrorMsg
            echomsg '(jobby) :JobbyList could not open a buffer'
            echohl None
            return
        endtry
        silent file [jobby]
        let b:jobby_list_buffer = 1
        setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
    endif
    " Output job status in job list to opened buffer.
    " * Arguments
    " * Current output
    let ctx = s:job_foreach('s:build_job_status_lines')
    if has_key(ctx, 'lines')
        call s:set_whole_lines(ctx.lines)
    else
        call s:set_whole_lines(['No jobs are running.'])
    endif
endfunction

function! s:build_job_status_lines(jobdict, ctx) abort
    let a:ctx.lines = get(a:ctx, 'lines', [])
    let status = job_status(a:jobdict.job)
    if has_key(a:jobdict, 'endtime')
        let reltime = reltime(a:jobdict.starttime, a:jobdict.endtime)
        let floattime = str2float(matchstr(reltimestr(reltime), '[0-9.]\+'))
        let line = printf('#%d (%s: %.1fs) %s',
        \           a:jobdict.id, status, floattime, a:jobdict.cmdline)
    else
        let line = printf('#%d %s',
        \           a:jobdict.id, a:jobdict.cmdline)
    endif
    let a:ctx.lines += [line]
endfunction

function! s:set_whole_lines(lines) abort
    %delete _
    call setline(1, a:lines)
endfunction

function! s:find_jobby_window() abort
    for bufnr in tabpagebuflist()
        if getbufvar(bufnr, 'jobby_list_buffer', v:null) isnot v:null
            return [bufwinnr(bufnr), bufnr]
        endif
    endfor
    return [-1, -1]
endfunction

function! jobby#clean() abort
    call s:job_inc_postpone_cb()
    try
        call s:do_clean()
    finally
        call s:job_dec_postpone_cb()
        call s:job_handle_postpone_cb()
    endtry
endfunction

function! s:do_clean() abort
    let re = '\v^(dead|fail)$'
    call s:job_filter('job_status(v:val.job) !~# ' . string(re))
endfunction



let s:job_list = []
let s:job_id = 0
let s:job_postpone_sem_count = 0
let s:job_postpone_cb_list = []

function! s:job_add(job, cmdline) abort
    let s:job_id += 1
    let s:job_list += [{
    \   'id': s:job_id,
    \   'job': a:job,
    \   'starttime': reltime(),
    \   'cmdline': a:cmdline
    \}]
endfunction

function! s:job_remove(job) abort
    call filter(s:job_list, 'v:val.job !=# a:job')
endfunction

" @throws
function! s:job_set(job, key, Value) abort
    let jobdict = s:get_jobdict_by_expr('v:val.job ==# job', {'job': a:job})
    if jobdict isnot v:null
        let jobdict[a:key] = a:Value
    else
        throw 's:job_set(): could not find jobdict by a:job'
    endif
endfunction

function! s:get_jobdict_by_expr(expr, ...) abort
    if a:0 && type(a:1) is type({})
        for [key, Value] in items(a:1)
            execute 'let' key '= Value'
            unlet Value
        endfor
    endif
    return get(filter(copy(s:job_list), a:expr), 0, v:null)
endfunction

function! s:get_job_by_expr(...) abort
    let jobdict = call('s:get_jobdict_by_expr', a:000)
    return (type(jobdict) ==# type({}) && has_key(jobdict, 'job') ?
    \           jobdict.job : v:null)
endfunction

function! s:get_job_by_jobid(jobid) abort
    return s:get_job_by_expr('v:val.id ==# ' . a:jobid)
endfunction

function! s:job_count() abort
    return len(s:job_list)
endfunction

function! s:job_filter(expr) abort
    call filter(s:job_list, a:expr)
endfunction

function! s:job_get_list() abort
    return map(copy(s:job_list), 'v:val.job')
endfunction

" @throws
function! s:job_foreach_break() abort
    throw 'JOBBY: BREAK'
endfunction

function! s:job_foreach(F, ...) abort
    let ctx = get(a:000, 0, {})
    try
        for jobdict in s:job_list
            call call(a:F, [jobdict, ctx])
        endfor
    catch /\<JOBBY: BREAK$/
    endtry
    return ctx
endfunction

function! s:job_inc_postpone_cb() abort
    let s:job_postpone_sem_count += 1
endfunction

function! s:job_dec_postpone_cb() abort
    if s:job_postpone_sem_count <=# 0
        throw 's:job_postpone_sem_count is already 0 or smaller.'
    endif
    let s:job_postpone_sem_count -= 1
endfunction

function! s:job_enabled_postpone_cb() abort
    return !!s:job_postpone_sem_count
endfunction

function! s:job_postpone(F, args) abort
    call add(s:job_postpone_cb_list, [a:F, a:args])
endfunction

function! s:job_handle_postpone_cb() abort
    if s:job_postpone_sem_count ># 0
        return
    endif
    while !empty(s:job_postpone_cb_list)
        let [F, args] = remove(s:job_postpone_cb_list, 0)
        call call(F, args)
    endwhile
endfunction


let &cpo = s:save_cpo
unlet s:save_cpo
