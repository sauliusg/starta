/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <run.h>

/* uses: */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <thrcode.h>
#include <alloccell.h>
#include <cxprintf.h>
#include <bcalloc.h>
#include <assert.h>
#include <bctraverse.h>
#include <allocx.h>

void *interpret_subsystem = &interpret_subsystem;

/* leave some stack cells unused at the begining and at the end of the
   stack -- to minimise segfaults and facilitate stack under/overflow
   diagnostics: */
#define STACK_SAFETY_MARGIN 5

/* internal state of the interpreter */
istate_t istate;

int trace = 0;

static size_t default_call_stack_length = 2000;
static size_t default_eval_stack_length = 2000;

static int stack_realloc_delta = 1000; /* in stackcells */

static int gc_debug = 0;

static void thrcode_print_stack( void );

size_t interpret_rstack_length( size_t length )
{
    ssize_t old_length = default_call_stack_length;
    default_call_stack_length = length;
    return old_length;
}

size_t interpret_estack_length( size_t length )
{
    ssize_t old_length = default_eval_stack_length;
    default_eval_stack_length = length;
    return old_length;
}

size_t interpret_stack_delta( size_t length )
{
    ssize_t old_length = stack_realloc_delta;
    stack_realloc_delta = length;
    return old_length;
}

static void make_istate( istate_t *new_istate, THRCODE *code,
                         int argc, char *argv[], char *env[],
                         cexception_t *ex )
{
    static int call_stack_size; /* stack size in bytes */
    static int eval_stack_size;

    freex( new_istate->call_stack );
    new_istate->call_stack = NULL;
    new_istate->call_stack_length = 0;
    new_istate->call_stack =
        callocx( sizeof(new_istate->call_stack[0]),
                 default_call_stack_length, ex );
    new_istate->call_stack_length = default_call_stack_length;
    call_stack_size =
        new_istate->call_stack_length * sizeof(new_istate->call_stack[0]);

    freex( new_istate->eval_stack );
    new_istate->eval_stack = NULL;
    new_istate->eval_stack_length = 0;
    new_istate->eval_stack =
        callocx( sizeof(new_istate->eval_stack[0]),
                 default_eval_stack_length, ex );
    new_istate->eval_stack_length = default_eval_stack_length;
    eval_stack_size =
        new_istate->eval_stack_length * sizeof(new_istate->eval_stack[0]);

    new_istate->thrcode = code;

    new_istate->bottom =
        new_istate->call_stack + new_istate->call_stack_length - 
        STACK_SAFETY_MARGIN;
    new_istate->fp = new_istate->gp = new_istate->sp = new_istate->bottom - 1;
    new_istate->top = new_istate->call_stack + STACK_SAFETY_MARGIN;

    memset( new_istate->call_stack, 0x55, call_stack_size );
    memset( new_istate->fp, 0, ( new_istate->bottom - new_istate->fp ) *
	    sizeof( *new_istate->fp ) );

    memset( new_istate->eval_stack, 0x00, eval_stack_size );

    new_istate->ep_bottom =
        new_istate->eval_stack + new_istate->eval_stack_length -
        STACK_SAFETY_MARGIN;

    new_istate->ep = new_istate->ep_bottom - 1;
    new_istate->ep_top = new_istate->eval_stack + STACK_SAFETY_MARGIN;

    new_istate->argc = argc;
    new_istate->argv = argv;
    new_istate->env = env;

    new_istate->code = thrcode_instructions( code );
    new_istate->code_length = thrcode_length( code );
    new_istate->static_data = thrcode_static_data( code, &istate.static_data_size );

    new_istate->ip = 0;
}

void *interpret_alloc( istate_t *is, ssize_t size )
{
    return thrcode_alloc_extra_data( is->thrcode, size );
}

void interpret( THRCODE *code, int argc, char *argv[], char *env[],
		cexception_t *ex )
{
    make_istate( &istate, code, argc, argv, env, ex );
    cexception_t inner;
    cexception_guard( inner ) {
        run( &inner );
        bcalloc_run_all_destructors( &inner );
        memset( istate.call_stack, 0, sizeof(istate.call_stack[0]) * istate.call_stack_length );
        memset( istate.eval_stack, 0, sizeof(istate.eval_stack[0]) * istate.eval_stack_length );
        thrcode_gc_mark_and_sweep( &inner );
        bccollect( &inner );
    }
    cexception_catch {
        int error_code = cexception_error_code( &inner );
        const char *message = cexception_message( &inner );
        inner.message = cxprintf( "Unhandled exception %d in the "
                                  "bytecode interpreter: %s",
                                  error_code, message );
        cexception_reraise( inner, ex );
    }
}

static int realloc_eval_stack( cexception_t * ex )
{
    /* The 'eval' stack should not have any references from the
       garbage-collected blocks, so it can be safely reallocated. */

    if( stack_realloc_delta <= 0 ) {
        return 0;
    } else {
        stackcell_t *old_eval_stack = istate.eval_stack;
        ssize_t old_eval_stack_length = istate.eval_stack_length;
        ssize_t delta, offset, full_offset;

        istate.eval_stack =
            reallocx( istate.eval_stack, sizeof(istate.eval_stack[0]) *
                      (istate.eval_stack_length + stack_realloc_delta), ex );

        istate.eval_stack_length += stack_realloc_delta;

        delta = (char*)istate.eval_stack - (char*)old_eval_stack;

        offset = stack_realloc_delta * sizeof(istate.eval_stack[0]);

        full_offset = offset + delta;

        /* We must use memmove() since the source and the destination
           overlap: */
        memmove( ((char*)istate.eval_stack) + offset, istate.eval_stack,
                 old_eval_stack_length * sizeof(istate.eval_stack[0]));

        istate.ep_bottom =
            (stackcell_t*)(((char*)istate.ep_bottom) + full_offset);
        istate.ep = (stackcell_t*)(((char*)istate.ep) + full_offset);
        istate.ep_top = istate.eval_stack + STACK_SAFETY_MARGIN;

        struct interpret_exception_t *current_xp;
        for( current_xp = istate.xp;
             current_xp != NULL;
             current_xp = current_xp->old_xp.ptr ) {
            current_xp->ep = (stackcell_t*)((char*)(current_xp->ep) +
                                            full_offset );
        }

#if 0
        memset( istate.eval_stack, 0xAA,
                stack_realloc_delta * sizeof(istate.eval_stack[0]));
#endif

        return 1;
    }
}

static int realloc_call_stack( cexception_t * ex )
{
    /* The 'call' can be pointed to from the evaluation stack,
       therefore references on the evaluation stack must be adjusted
       after the reallocation. */

    if( stack_realloc_delta <= 0 ) {
        return 0;
    } else {
        stackcell_t *old_call_stack = istate.call_stack;
        stackcell_t *old_call_limit =
            istate.call_stack + istate.call_stack_length;
        stackcell_t *ep, *ep_limit, *sp, *sp_limit;
        ssize_t old_call_stack_length = istate.call_stack_length;
        ssize_t delta, offset, full_offset;

        istate.call_stack =
            reallocx( istate.call_stack, sizeof(istate.call_stack[0]) *
                      (istate.call_stack_length + stack_realloc_delta), ex );

        istate.call_stack_length += stack_realloc_delta;

        offset = stack_realloc_delta * sizeof(istate.call_stack[0]);

        /* We must use memmove() since the source and the destination
           overlap: */
        memmove( ((char*)istate.call_stack) + offset, istate.call_stack,
                 old_call_stack_length * sizeof(istate.call_stack[0]));

        delta = (char*)istate.call_stack - (char*)old_call_stack;

        full_offset = offset + delta;

        /* Adjust pointers on the evaluation stack so that they point
           to the moved elements on the newly reallocated call
           stack: */
        if( full_offset != 0 ) {
            ep_limit = istate.eval_stack + istate.eval_stack_length;
            for( ep = istate.eval_stack; ep < ep_limit; ep++ ) {
                if( ep->PTR >= (void*)old_call_stack &&
                    ep->PTR < (void*)old_call_limit ) {
                    ep->PTR = (char*)(ep->PTR) + full_offset;
                    //printf( "<<<< Moving on eval: %p -> %p\n", ep->PTR-full_offset, ep->PTR );
                }
            }
            sp_limit = istate.call_stack + istate.call_stack_length;
            for( sp = istate.call_stack; sp < sp_limit; sp++ ) {
                //printf( ">>> checking call stack %p, PTR = %p\n", sp, sp->PTR );
                if( sp->PTR >= (void*)old_call_stack &&
                    sp->PTR < (void*)old_call_limit ) {
                    sp->PTR = (char*)(sp->PTR) + full_offset;
                    //printf( ">>> Moving on call: %p -> %p\n", sp->PTR-full_offset, sp->PTR );
                }
            }
        }

#if 0
        printf( "reallocating call stack, length = %d, delta = %d, full_offset = %d\n",
                istate.call_stack_length, delta, full_offset );
        printf( "old call stack = %p, new call stack = %p\n",
                old_call_stack, istate.call_stack );
#endif

        istate.bottom = (stackcell_t*)((char*)(istate.bottom) + full_offset);
        istate.fp = (stackcell_t*)((char*)(istate.fp) + full_offset);
        istate.sp = (stackcell_t*)((char*)(istate.sp) + full_offset);
        istate.gp = (stackcell_t*)((char*)(istate.gp) + full_offset);
        istate.top = istate.call_stack + STACK_SAFETY_MARGIN;

        /* Adjust exception structure pointers: */
        
        struct interpret_exception_t *current_xp;
        for( current_xp = istate.xp;
             current_xp != NULL;
             current_xp = current_xp->old_xp.ptr ) {

            current_xp->fp = (stackcell_t*)((char*)(current_xp->fp) +
                                            full_offset );

            current_xp->sp = (stackcell_t*)((char*)(current_xp->sp) +
                                            full_offset );
        }
#if 1
        memset( istate.call_stack, 0x55,
                stack_realloc_delta * sizeof(istate.call_stack[0]));
#endif

        return 1;
    }
}

static void check_runtime_stacks( cexception_t * ex )
{
    if( istate.ep < istate.ep_top ) {
        if( ! realloc_eval_stack( ex )) {
            interpret_raise_exception_with_static_message
                ( INTERPRET_ESTACK_OVERFLOW,
                  "evaluation stack overflow",
                  /* module = */ NULL,
                  SL_EXCEPTION_INTERPRETER_ERROR, ex );
        }
    }
    if( istate.ep > istate.ep_bottom - 1 ) {
	interpret_raise_exception_with_static_message(
	    INTERPRET_ESTACK_UNDERFLOW,
	    "evaluation stack underflow",
	    /* module = */ NULL,
	    SL_EXCEPTION_INTERPRETER_ERROR, ex );
    }

    if( istate.sp < istate.top ) {
        if( ! realloc_call_stack( ex )) {
            interpret_raise_exception_with_static_message
                ( INTERPRET_RSTACK_OVERFLOW,
                  "return stack overflow",
                  /* module = */ NULL,
                  SL_EXCEPTION_INTERPRETER_ERROR, ex );
        }
    }
    if( istate.sp > istate.bottom - 1 ) {
	interpret_raise_exception_with_static_message(
	    INTERPRET_RSTACK_UNDERFLOW,
	    "return stack underflow",
	    /* module = */ NULL,
	    SL_EXCEPTION_INTERPRETER_ERROR, ex );
    }
}

void run( cexception_t *ex )
{
    cexception_t inner;
    register int (*function)( void );

    istate.ex = &inner;

    function = istate.code[0].fn;

    while( function ) {
	cexception_guard( inner ) {
	    while( function ) {
		int ret = (*function)();
		istate.ip += ret;
		function = istate.code[istate.ip].fn;
		if( thrcode_stackdebug_is_on()) {
		    thrcode_print_stack();
		}
		check_runtime_stacks( &inner );
	    }
	}
	cexception_catch {
            interpret_reraise_exception( inner, ex );
            function = istate.code[istate.ip].fn;
	}
    }
}

void thrcode_trace_on( void )
{
    trace = 1;
}

void thrcode_trace_off( void )
{
    trace = 0;
}

int thrcode_trace_is_on( void )
{
    return trace;
}

void thrcode_gc_debug_on( void )
{
    gc_debug = 1;
}

void thrcode_gc_debug_off( void )
{
    gc_debug = 0;
}

int thrcode_gc_debug_is_on( void )
{
    return gc_debug;
}

int interpret_exception_size()
{
    return sizeof(interpret_exception_t);
}

void interpret_raise_exception_with_bcalloc_message( int error_code,
						     char *message,
						     char *module_id,
						     int exception_id,
						     cexception_t *ex )
{
    char *msg = bcalloc_blob( strlen(message) + 1, ex );

    if( msg ) {
	strcpy( msg, message );
	interpret_raise_exception( error_code, msg, module_id,
				   exception_id, ex );
    } else {
	interpret_raise_exception_with_static_message( error_code, message,
						       module_id, exception_id,
						       ex );
    }
}

static struct {
    alloccell_t alloc_header;
    char text[100];
} err_message = {
    {BC_MAGIC}
};

void interpret_raise_exception_with_static_message( int error_code,
						    char *message,
						    char *module_id,
						    int exception_id,
						    cexception_t *ex )
{
    strncpy( err_message.text, message, sizeof( err_message.text ));
    interpret_raise_exception( error_code, err_message.text,
			       module_id, exception_id, ex );
}

void interpret_raise_exception( int error_code,
				char *message,
				char *module_id,
				int exception_id,
				cexception_t *ex )
{
    interpret_exception_t *rg_store;

    assert( !message || ((alloccell_t*)message)[-1].magic == BC_MAGIC );

    if( istate.xp == 0 ) {
        if( ex ) {
            ex->exception_id = exception_id;
            ex->module_id = module_id;
        }
	if( message ) {
	    cexception_raise_in( ex, interpret_subsystem,
				 error_code, message );
	} else {
            snprintf( err_message.text, sizeof(err_message.text)-1,
                      "Unhandled exception %d in the bytecode interpreter",
                      error_code );
	    cexception_raise_in( ex, interpret_subsystem,
				 error_code, err_message.text );
	}
    }

    rg_store = istate.xp;
    rg_store->error_code = error_code;
    rg_store->message.ptr = message;
    rg_store->module = module_id;
    rg_store->exception_id = exception_id;

#if 1
    memset( istate.ep, 0, (rg_store->ep - istate.ep) * sizeof(istate.ep[0]) );
#else
    {
	ssize_t i;
	ssize_t limit = rg_store->ep - istate.ep;

	for( i = 0; i < limit; i ++ ) {
	    STACKCELL_ZERO_PTR( istate.ep[i] );
	}
    }
#endif

    istate.xp = rg_store->old_xp.ptr;
    istate.ip = rg_store->ip + rg_store->catch_offset;
    istate.sp = rg_store->sp;
    istate.ep = rg_store->ep;
    istate.fp = rg_store->fp;
}

void interpret_reraise_exception( cexception_t old_ex,
                                  cexception_t *ex )
{
    interpret_exception_t *rg_store;
    int error_code = cexception_error_code( &old_ex );
    const char *message = cexception_message( &old_ex );
    const char *module_id = cexception_module_id( &old_ex );
    int exception_id = cexception_exception_id( &old_ex );

    assert( !message || ((alloccell_t*)message)[-1].magic == BC_MAGIC );

    if( istate.xp == 0 ) {
        if( ex ) {
            ex->exception_id = exception_id;
            ex->module_id = module_id;
        }
	if( message ) {
	    cexception_raise_in( ex, interpret_subsystem,
				 error_code, message );
	} else {
            snprintf( err_message.text, sizeof(err_message.text)-1,
                      "Unhandled exception %d in the bytecode interpreter",
                      error_code );
	    cexception_raise_in( ex, interpret_subsystem,
				 error_code, err_message.text );
	}
    }

    rg_store = istate.xp;
    rg_store->error_code = error_code;
    rg_store->message.ptr = (char*)message;
    rg_store->module = (char*)module_id;
    rg_store->exception_id = exception_id;

#if 1
    memset( istate.ep, 0, (rg_store->ep - istate.ep) * sizeof(istate.ep[0]) );
#else
    {
	ssize_t i;
	ssize_t limit = rg_store->ep - istate.ep;

	for( i = 0; i < limit; i ++ ) {
	    STACKCELL_ZERO_PTR( istate.ep[i] );
	}
    }
#endif

    istate.xp = rg_store->old_xp.ptr;
    istate.ip = rg_store->ip + rg_store->catch_offset;
    istate.sp = rg_store->sp;
    istate.ep = rg_store->ep;
    istate.fp = rg_store->fp;
}

static char *line = "--------------------------------------------";

static void thrcode_dump_single_stack( stackcell_t *stack,
				       stackcell_t *bottom )
{
    stackcell_t *curr;

    for( curr = stack; curr < bottom; curr++ ) {
	char *ptr = curr->PTR;
	if( stack == istate.sp ) {
	    printf( "%10p %4d %4d %10d  ",
		    curr, istate.bottom-curr-1, curr-istate.fp, curr->num.i );
	} else
	if( stack == istate.ep ) {
	    printf( "%10p %4d %4s %10d  ",
		    curr, istate.ep_bottom-curr-1, "", curr->num.i );
	} else {
	    printf( "%10p %4s %4s %10d  ",
		    curr, "", "", curr->num.i );
	}

	if( ptr ) {
	    printf( "%10p ", ptr );
	    if( ptr < (char*)istate.bottom + STACK_SAFETY_MARGIN &&
		ptr > (char*)istate.top - STACK_SAFETY_MARGIN ) {
		printf( "S" );
	    } else
	    if( ptr > (char*)istate.code &&
		ptr <= (char*)istate.code + istate.code_length ) {
		printf( "C" );
	    } else
	    if( bcalloc_is_in_heap( ptr )) {
		alloccell_t *ac = (alloccell_t*)ptr;
		if( ac[-1].magic == BC_MAGIC ) {
		    printf( "H" );
		} else {
		    printf( "!" );
		}
	    } else {
		if( ptr >= (char*)istate.static_data &&
		    ptr < (char*)istate.static_data +
		    istate.static_data_size ) {
		    printf( "D" );
		} else {
		    printf( "?" );
		}
	    }
	}
	printf( "\n" );
    }
}

static void thrcode_print_single_stack( stackcell_t *stack,
					stackcell_t *bottom )
{
    if( stack == istate.sp ) {
	printf( "sp_top = %p, sp_bottom = %p, sp = %p\n",
		istate.top, istate.bottom, istate.sp );
    } else
    if( stack == istate.ep ) {
	printf( "ep_top = %p, ep_bottom = %p, ep = %p\n",
		istate.ep_top, istate.ep_bottom, istate.ep );
    }
    thrcode_dump_single_stack( stack, bottom );
    printf( "\n" );
}

void interpreter_print_eval_stack()
{
    thrcode_dump_single_stack( istate.ep+1, istate.ep_bottom );
}

static void thrcode_print_stack( void )
{
    printf( "\n%s\n", line );
    thrcode_print_single_stack( istate.sp, istate.bottom );
    thrcode_print_single_stack( istate.ep, istate.ep_bottom );
}

static void thrcode_traverse_stack( stackcell_t *stack,
				    stackcell_t *bottom )
{
    stackcell_t *curr;

    for( curr = stack; curr < bottom; curr++ ) {
	char *ptr = curr->PTR;
	if( ptr ) {
	    if( ( ptr >= (char*)(istate.bottom + STACK_SAFETY_MARGIN) ||
		  ptr <  (char*)(istate.top - STACK_SAFETY_MARGIN) ) &&
		( ptr <  (char*)istate.code ||
		  ptr >= (char*)(istate.code + istate.code_length) ) &&
		bcalloc_is_in_heap( ptr )) {
		alloccell_t *ac = (alloccell_t*)ptr;
		assert( ac[-1].magic == BC_MAGIC );
		bctraverse( ptr );
	    }
	}
    }
}

void thrcode_gc_mark_and_sweep( cexception_t *ex )
{
    if( gc_debug )
	printf( ">>> Starting mark & sweep\n" );

    bcalloc_reset_allocated_nodes();
    bctraverse( istate.xp );
    bctraverse( istate.save_xp );
    thrcode_traverse_stack( istate.sp, istate.bottom );
    thrcode_traverse_stack( istate.ep, istate.ep_bottom );
    bccollect( ex );

    if( gc_debug )
	printf( ">>> Finished mark & sweep\n" );
}

void thrcode_run_subroutine( istate_t *istate, ssize_t code_offset, 
                             cexception_t *ex )
{
    istate_t save_istate = *istate;

    /* push the return address, an address of a '0' opcode that will
       cause a sub-interpreter to terminate: */
    (--istate->sp)->num.ssize = istate->code_length - 1;
    /* push old frame pointer: */
    (--istate->sp)->ptr = istate->fp;
    /* set the frame pointer for the called procedure: */
    istate->fp = istate->sp;
    STACKCELL_ZERO_PTR( istate->sp[1] );

    /* Set the IP to the address of the called subroutine: */
    istate->ip = code_offset;
    assert( !istate->save_xp );
    istate->save_xp = istate->xp;
    istate->xp = NULL;

    /* Invoke the sub-interpreter: */
    /* int old_trace = trace; trace = 1; */
    cexception_t inner;
    cexception_guard( inner ) {
        run( &inner );
    }
    cexception_catch {
        /* trace = old_trace; */
        istate->xp = save_istate.xp;
        istate->save_xp = NULL;
        istate->ip = save_istate.ip;
        istate->ex = save_istate.ex;
        cexception_reraise( inner, ex );
    }
    /* trace = old_trace; */

    /* Restore the previous interpreter state: */
    istate->xp = save_istate.xp;
    istate->save_xp = NULL;
    istate->ip = save_istate.ip;
    istate->ex = save_istate.ex;
}

static int in_gc = 0;

void thrcode_run_destructor_if_needed( istate_t *istate,
                                       alloccell_t *hdr,
                                       cexception_t * ex )
{
    if( in_gc )
        return;

    in_gc = 1;

    if( hdr->vmt_offset != 0 ) {
        ssize_t vtable_offset = hdr->vmt_offset[1];
        ssize_t *vtable =
            (ssize_t*)(istate->static_data + vtable_offset);
        if( vtable[0] > 0 && vtable[1] != 0 ) {
#if 0
            printf( ">>> garbage collector should call destructor "
                    "at offset %d\n", vtable[1] );
#endif
            /* Push the 'self' reference to the destructed object
               onto the stack: */
            istate->ep--;
            STACKCELL_SET_ADDR( istate->ep[0], hdr+1 );
            /* Invoke the destructor: */
            ssize_t code_offset = vtable[1];
            cexception_t inner;

            cexception_guard( inner ) {
                thrcode_run_subroutine( istate, code_offset, &inner );
            }
            cexception_catch {
                const char *message = cexception_message( &inner );
                int errcode = cexception_error_code( &inner );
                fprintf( stderr, "exception (code %d) raised in destructor: %s\n",
                         errcode, message );
                /* We sould not reraise the exception, since then
                   garbage collection will not be properly finished.*/
                //in_gc = 0;
                //cexception_reraise( inner, ex );
            }
            hdr->vmt_offset = 0; // Not an object any more; prevents
                                 // running destructor twice.
        }
    }

    in_gc = 0;
}
