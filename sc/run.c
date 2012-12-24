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

void *interpret_subsystem = &interpret_subsystem;

/* A size of a runtime-allocated data to be allcoated in one chunk: */
#define RUNTIME_DATA_NODE_CHUNK 1024

struct runtime_data_node {
    struct runtime_data_node *next;
    union {
        double d;
        ldouble ld;
    } value;
};

/* leave some stack cells unused at the begining and at the end of the
   stack -- to minimise segfaults and facilitate stack under/overflow
   diagnostics: */
#define STACK_SAFETY_MARGIN 4

/* internal state of the interpreter */
istate_t istate;

int trace = 0;

static int gc_debug = 0;

static void thrcode_print_stack( void );

static void make_istate( istate_t *new_istate, THRCODE *code,
                         int argc, char *argv[], char *env[] )
{
    static stackcell_t call_stack[2000];
    static stackcell_t eval_stack[2000];
    const int call_stack_size = sizeof(call_stack); /* stack size in bytes */
    const int call_stack_length = call_stack_size/sizeof(stackcell_t);
                                          /* stack lenght, i.e. number
					     of the available stack cells */
    const int eval_stack_size = sizeof(eval_stack);
    const int eval_stack_length = eval_stack_size/sizeof(stackcell_t);

    new_istate->bottom = call_stack + call_stack_length - STACK_SAFETY_MARGIN;
    new_istate->fp = new_istate->gp = new_istate->sp = new_istate->bottom - 1;
    new_istate->top = call_stack + STACK_SAFETY_MARGIN;

    memset( call_stack, 0x55, call_stack_size );
    memset( new_istate->fp, 0, ( new_istate->bottom - new_istate->fp ) *
	    sizeof( *new_istate->fp ) );

    memset( eval_stack, 0x00, sizeof(eval_stack) );

    new_istate->ep_bottom = eval_stack + eval_stack_length -
        STACK_SAFETY_MARGIN;

    new_istate->ep = new_istate->ep_bottom - 1;
    new_istate->ep_top = eval_stack + STACK_SAFETY_MARGIN;

    new_istate->argc = argc;
    new_istate->argv = argv;
    new_istate->env = env;

    new_istate->extra_data = NULL;
}

static void cleanup_istate( istate_t *istate )
{
    runtime_data_node *current, *next;

    current = istate->extra_data;
    while( current ) {
        next = current->next;
        free( current );
        current = next;
    }
    memset( istate, 0, sizeof(*istate) );
    assert( istate->env == NULL );
}

void *interpret_alloc( istate_t *is, ssize_t size )
{
    runtime_data_node *current = is->extra_data;

    is->extra_data = calloc( 1, sizeof(*is->extra_data) + size -
                             sizeof(is->extra_data->value) );

    if( is->extra_data ) {
        is->extra_data->next = current;
        return &(is->extra_data->value);
    } else {
        is->extra_data = current;
        return NULL;
    }
}

void interpret( THRCODE *code, int argc, char *argv[], char *env[],
		cexception_t *ex )
{
    make_istate( &istate, code, argc, argv, env );
    run( code, ex );
    cleanup_istate( &istate );
}

static void check_runtime_stacks( cexception_t * ex )
{
    if( istate.ep < istate.ep_top ) {
	interpret_raise_exception_with_static_message(
	    INTERPRET_ESTACK_OVERFLOW,
	    "evaluation stack overflow",
	    /* module = */ NULL,
	    SL_EXCEPTION_INTERPRETER_ERROR, ex );
    }
    if( istate.ep > istate.ep_bottom - 1 ) {
	interpret_raise_exception_with_static_message(
	    INTERPRET_ESTACK_UNDERFLOW,
	    "evaluation stack underflow",
	    /* module = */ NULL,
	    SL_EXCEPTION_INTERPRETER_ERROR, ex );
    }

    if( istate.sp < istate.top ) {
	interpret_raise_exception_with_static_message(
	    INTERPRET_RSTACK_OVERFLOW,
	    "return stack overflow",
	    /* module = */ NULL,
	    SL_EXCEPTION_INTERPRETER_ERROR, ex );
    }
    if( istate.sp > istate.bottom - 1 ) {
	interpret_raise_exception_with_static_message(
	    INTERPRET_RSTACK_UNDERFLOW,
	    "return stack underflow",
	    /* module = */ NULL,
	    SL_EXCEPTION_INTERPRETER_ERROR, ex );
    }
}

void run( THRCODE *code, cexception_t *ex )
{
    cexception_t inner;
    register int (*function)( void );

    istate.ex = ex;
    istate.code = thrcode_instructions( code );
    istate.code_length = thrcode_length( code );
    istate.ip = 0;
    istate.static_data = thrcode_static_data( code, &istate.static_data_size );
    
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
		check_runtime_stacks( ex );
	    }
	}
	cexception_catch {
	    char *message = (char*)cexception_message( &inner );
	    int error_code = cexception_error_code( &inner );
	    if( message ) {
		interpret_raise_exception_with_static_message(
				       error_code, message,
				       /* module = */ NULL,
				       SL_EXCEPTION_EXTERNAL_LIB_ERROR, ex );
	    } else {
		interpret_raise_exception(
				       error_code, /* err_message = */ NULL,
				       /* module = */ NULL,
				       SL_EXCEPTION_EXTERNAL_LIB_ERROR, ex );
	    }
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
    char *msg = bcalloc_blob( strlen(message) + 1 );

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
	if( message ) {
	    cexception_raise_in( ex, interpret_subsystem,
				 INTERPRET_UNHANDLED_EXCEPTION,
				 cxprintf( "Unhandled exception %d in the "
					   "bytecode interpreter: %s",
					   error_code, message ));
	} else {
	    cexception_raise_in( ex, interpret_subsystem,
				 INTERPRET_UNHANDLED_EXCEPTION,
				 cxprintf( "Unhandled exception %d in the "
					   "bytecode interpreter",
					   error_code ));
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

void thrcode_gc_mark_and_sweep( void )
{
    if( gc_debug )
	printf( ">>> Starting mark & sweep\n" );
    bcalloc_reset_allocated_nodes();
    bctraverse( istate.xp );
    thrcode_traverse_stack( istate.sp, istate.bottom );
    thrcode_traverse_stack( istate.ep, istate.ep_bottom );
    bccollect();
    if( gc_debug )
	printf( ">>> Finished mark & sweep\n" );
}
