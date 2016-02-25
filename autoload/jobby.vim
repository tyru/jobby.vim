scriptencoding utf-8
let s:save_cpo = &cpo
set cpo&vim

let g:jobby#list_buf_open_cmd = get(g:, 'jobby#list_buf_open_cmd', '5new')


" @throws
function! jobby#run(cmdline, args) abort
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
        echom 'Run(failure): ' . a:cmdline
        return
    endif
    call job_setoptions(job, {
    \   'exit-cb': 'jobby#__exit_cb__',
    \   'stoponexit': 'kill'
    \})
    " Add spawned job to job list.
    call s:job_add(job, a:cmdline)
    " Message
    echom 'Run(success): ' . a:cmdline
endfunction

function! jobby#__exit_cb__(job, ...) abort
    " Output 'Done' message with command-line string.
    let ctx = s:job_foreach('s:get_cmdline_by_job', {'job': a:job})
    if has_key(ctx, 'cmdline') && has_key(ctx, 'id')
        echo 'Done: ' . ctx.cmdline
    endif
    call s:job_set(a:job, 'endtime', reltime())
endfunction

function! s:get_cmdline_by_job(jobdict, ctx) abort
    if a:jobdict.job ==# a:ctx.job
        let a:ctx.cmdline = a:jobdict.cmdline
        let a:ctx.id = a:jobdict.id
        call s:job_foreach_break()
    endif
endfunction

" @throws
function! jobby#stop(cmdline) abort
    " Stop job.
    if a:cmdline =~# '^[0-9]\+$'
        " Job ID
        if s:job_stop_forcefully(a:cmdline + 0)
            echom 'Stop(success): ' . a:cmdline
        else
            echom 'Stop(failure): ' . a:cmdline
        endif
    else
        " TODO: Find matching jobs from job list.
        throw 'not implemented yet'
    endif
endfunction

function! jobby#list() abort
    let jobby_winnr = -1
    for bufnr in tabpagebuflist()
        if getbufvar(bufnr, 'jobby_list_buffer', v:null) isnot v:null
            let jobby_winnr = bufwinnr(bufnr)
            break
        endif
    endfor
    if jobby_winnr > 0
        " Jump to the existing window.
        execute jobby_winnr 'wincmd w'
    else
        " Open a new jobby buffer & window.
        try
            execute g:jobby#list_buf_open_cmd
        catch
            echohl ErrorMsg
            echomsg 'Could not open list buffer'
            echohl None
            return
        endtry
        silent file '[jobby]'
        let b:jobby_list_buffer = 1
        setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
    endif
    " Output job status in job list to opened buffer.
    " * Arguments
    " * Current output
    let ctx = s:job_foreach('s:setline_job_status')
    if !has_key(ctx, 'count')
        call setline(1, 'No jobs are running.')
    endif
endfunction

function! s:setline_job_status(jobdict, ctx) abort
    let a:ctx.count = get(a:ctx, 'count', 0) + 1
    let lnum = (a:ctx.count ==# 1 ? 1 : line('$') + 1)
    let status = job_status(a:jobdict.job)
    if !has_key(a:jobdict, 'endtime')
        " XXX
        call jobby#__exit_cb__(a:jobdict.job, job_status(a:jobdict.job))
    endif
    let reltime = reltime(a:jobdict.starttime, a:jobdict.endtime)
    let floattime = str2float(matchstr(reltimestr(reltime), '[0-9.]\+'))
    let line = printf('(%s: %.1fs) %s', status, floattime, a:jobdict.cmdline)
    call setline(lnum, line)
endfunction

function! jobby#clean() abort
    let re = '\v^(dead|fail)$'
    call s:job_filter('job_status(v:val.job) !~# ' . string(re))
endfunction




let s:job_list = []
let s:job_id = 0

function! s:job_add(job, cmdline) abort
    let s:job_id += 1
    let s:job_list += [{
    \   'id': s:job_id,
    \   'job': a:job,
    \   'starttime': reltime(),
    \   'cmdline': a:cmdline
    \}]
endfunction

" @throws
function! s:job_set(job, key, Value) abort
    let jobdict = s:get_jobdict_by_job(a:job)
    if jobdict isnot v:null
        let jobdict[a:key] = a:Value
    else
        throw 's:job_set(): could not find jobdict by a:job'
    endif
endfunction

function! s:get_jobdict_by_job(job) abort
    return get(filter(copy(s:job_list), 'v:val.job ==# a:job'), 0, v:null)
endfunction

function! s:job_count() abort
    return len(s:job_list)
endfunction

" @throws
function! s:job_stop_forcefully(index) abort
    if a:index < 0 || a:index >= s:job_count()
        throw 'internal error: out of range (s:job_list[index])'
    endif

    let job = s:job_list[a:index].job
    let start = reltime()
    let maxtimeSec = 5
    let waittime = 50
    let sleepcmd = 'sleep %sm'

    " Stop job.
    call job_stop(job, 'term')
    execute printf(sleepcmd, waittime)
    while job_status(job)
        let waittime = waittime * 2
        let duraSec = matchstr(reltime(start, reltime()), '\d\+')
        if duraSec >= maxtimeSec
            return 0
        endif
    endwhile

    " Remove job from job list.
    let id = s:job_list[a:index].id
    call filter(s:job_list, 'v:val.id !=# id')
    return 1
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


let &cpo = s:save_cpo
unlet s:save_cpo
