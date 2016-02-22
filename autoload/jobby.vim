scriptencoding utf-8
let s:save_cpo = &cpo
set cpo&vim


function! jobby#run(cmdline, args) abort
    if a:cmdline[0] ==# ':'
        " TODO: Run Ex command in another Vim.
        " let job = job_start(...)
        throw 'not implemented yet'
    else
        " Run external command.
        let args = ['/bin/sh', '-c', a:cmdline . ' </dev/null >/dev/null']
        let job = job_start(args)
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

function! jobby#__exit_cb__(job, status) abort
    " TODO: Remove job from job list.
    echomsg ''
endfunction

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
    " Show job status in job list.
    " * Arguments
    " * Current output
    let ctx = s:job_foreach('s:do_echo')
    if ctx.count ==# 0
        echom 'No jobs are running.'
    endif
endfunction

function! s:do_echo(job, cmdline, ctx) abort
    let a:ctx.count = get(a:ctx, 'count', 0) + 1
    let status = job_status(a:job)
    echom printf('(%s) %s', status, a:cmdline)
endfunction




let s:job_list = []
let s:job_id = 0

function! s:job_add(job, cmdline) abort
    let s:job_id += 1
    let s:job_list += [{
    \   'id': s:job_id,
    \   'job': a:job,
    \   'cmdline': a:cmdline
    \}]
endfunction

function! s:job_count() abort
    return len(s:job_list)
endfunction

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

function! s:job_get_list() abort
    return map(copy(s:job_list), 'v:val.job')
endfunction

function! s:job_foreach(F) abort
    let ctx = {}
    for jobdict in s:job_list
        call call(a:F, [jobdict.job, jobdict.cmdline, ctx])
    endfor
    return ctx
endfunction


let &cpo = s:save_cpo
unlet s:save_cpo
