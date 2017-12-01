

#include <stdlib.h>
#include <stdio.h>
#include <instruction_args.h>
#include <run.h>

#include <EXTERN.h>
#include <perl.h>

char *OPCODES[] = {
    "RUN",
    "FINISH",
    NULL
};

int trace = 0;

static istate_t *istate_ptr;

#define istate (*istate_ptr)

#ifndef TRACE
#define TRACE
#endif

#if 0
#define EXCEPTION (NULL)
#else
#define EXCEPTION (istate.ex)
#endif

#ifdef TRACE_FUNCTION
#undef TRACE_FUNCTION
#endif

#ifdef TRACE
#define TRACE_FUNCTION() \
    if( trace ) printf( "%s\t" \
                        "%4ld(%9p) %4ld(%9p) " \
                        "%4ld(%9p) %4ld(%9p) " \
                        "%4ld(%9p) %4ld(%9p) ...\n", \
                        __FUNCTION__, \
                        (long)istate.ep[0].num.i, istate.ep[0].PTR, \
                        (long)istate.ep[1].num.i, istate.ep[1].PTR, \
                        (long)istate.ep[2].num.i, istate.ep[2].PTR, \
                        (long)istate.ep[3].num.i, istate.ep[3].PTR, \
                        (long)istate.ep[4].num.i, istate.ep[4].PTR, \
                        (long)istate.ep[5].num.i, istate.ep[5].PTR )
#else
#define TRACE_FUNCTION()
#endif

int init( istate_t *global_istate )
{
    istate_ptr = global_istate;
    PERL_SYS_INIT3(&global_istate->argc,&global_istate->argv,&global_istate->env);
    return 0;
}

int trace_on( int trace_flag )
{
    int old_trace_flag = trace;
    trace = trace_flag;
    return old_trace_flag;
}

/*
 * RUN Run a Perl code. Take a string with a Perl program from the
 *     stack, compile and run it.
 * 
 * bytecode:
 * RUN
 * 
 * stack:
 * string -->
 */

/*
  Method described and code sample provided at:
  http://perldoc.perl.org/perlembed.html
*/

int RUN( INSTRUCTION_FN_ARGS )
{
    char * perl_code = STACKCELL_PTR( istate.ep[0] );
    char *embedding[] = { "", "-e", "0" };
    PerlInterpreter *my_perl;

    TRACE_FUNCTION();

    my_perl = perl_alloc();
    perl_construct( my_perl );
    perl_parse(my_perl, NULL, 3, embedding, NULL);
    PL_exit_flags |= PERL_EXIT_DESTRUCT_END;
    perl_run(my_perl);
    eval_pv(perl_code, TRUE);
    perl_destruct(my_perl);
    perl_free(my_perl);

    STACKCELL_ZERO_PTR( istate.ep[0] );
    istate.ep ++;
    
    return 1;
}

/*
 * FINISH  Finish work woth the Perl system just before terminating the program
 * 
 * bytecode:
 * FINISH
 * 
 * string -->
 */

int FINISH( INSTRUCTION_FN_ARGS )
{
    TRACE_FUNCTION();

    PERL_SYS_TERM();

    return 1;
}
