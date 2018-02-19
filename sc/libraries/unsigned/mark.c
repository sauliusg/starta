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
#include <opcodes.h>
#include <thrcode.h>
#include <alloccell.h>
#include <cxprintf.h>
#include <bcalloc.h>
#include <assert.h>
#include <bctraverse.h>
#include <allocx.h>

/* leave some stack cells unused at the begining and at the end of the
   stack -- to minimise segfaults and facilitate stack under/overflow
   diagnostics: */
#define STACK_SAFETY_MARGIN 5

static int gc_debug = 0;

static void thrcode_traverse_stack( stackcell_t *stack,
				    stackcell_t *bottom )
{
    stackcell_t *curr;

    for( curr = stack; curr < bottom; curr++ ) {
	char *ptr = curr->PTR;
	if( ptr ) {
	    if( ( ptr >= (char*)(istate_ptr->bottom + STACK_SAFETY_MARGIN) ||
		  ptr <  (char*)(istate_ptr->top - STACK_SAFETY_MARGIN) ) &&
		( ptr <  (char*)istate_ptr->code ||
		  ptr >= (char*)(istate_ptr->code + istate_ptr->code_length) ) &&
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
    bctraverse( istate_ptr->xp );
    bctraverse( istate_ptr->save_xp );
    thrcode_traverse_stack( istate_ptr->sp, istate_ptr->bottom );
    thrcode_traverse_stack( istate_ptr->ep, istate_ptr->ep_bottom );
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
                /* fprintf( stderr, "!!! exception raised in destructor\n" ); */
                in_gc = 0;
                cexception_reraise( inner, ex );
            }
        }
    }

    in_gc = 0;
}
