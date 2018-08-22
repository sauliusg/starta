/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* dnodes -- nodes representing variable and function declarations */
/* dnode tree is created by the parser (snail.y) */
/* From the dnode tree the symbol table is build */

/* exports: */
#include <dnode.h>

/* uses: */
#include <cexceptions.h>
#include <tnode_compat.h>
#include <vartab.h>
#include <typetab.h>
#include <cvalue_t.h>
#include <stringx.h>
#include <string.h>
#include <assert.h>
#include <yy.h>
#include <stackcell.h>
#include <allocx.h>

/* "declared name" can be a name of a variable, constant, function,
   module, label -- in short, anything that can be associated with a
   value or an offset (which may be treated as a kind of value).  Note
   that types are not represented by dnodes, but instead by tnodes. */

struct DNODE {
    /* Next and previous DNODEs in the allocated DNODE list; used to
       keep track of the allocated DNODEs and to prevent memory
       leaks: */
    DNODE *next_alloc, *prev_alloc;

    char *name;            /* The declared name; this name is supposed
                              to be unique in a current scope */
    char *filename;        /* Name of the file in which a module named
                              in the "name" field is declared; a
                              unique pair identifying a module is
                              (name, filename). */
    char *synonim;         /* Synonim name for different
                              implementations of parametrised modules. */
    dnode_flag_t flags;
    TNODE *tnode;          /* type descriptor node, describes the type
			      of the variable, or the type of the
			      return value the function, or the type
			      of the function. */
    int scope;             /* number of the lexical scope in which the
			      variable was declared */
    ssize_t offset;        /* offset of the field within the
			      structure, or offset of the local
			      variable on the stack frame, or address
			      of the function in the bytecode, or
			      offset of the virtual method in the
			      virtual method table. */
    int rcount;            /* reference count */
    int rcount2;           /* The second reference count, used to
                              count references from cycles. If all
                              references come exclusively from other
                              symbol table nodes, and there are no
                              more roots elswehere in the code, we
                              should have rcount == rcount2.  */
    ssize_t code_length;   /* number of opcodes in the following
			      opcode array */
    thrcode_t *code;       /* code fragment that implements an
			      operator or an inline function, if the
			      current dnode represents one of such
			      objects. */
    FIXUP *code_fixups;    /* Fixups that need to be applied to the
			      code fragment from the 'code' field,
			      after it is emitted. May contain, e.g.,
			      array element size or alignment values
			      that were not known during compilation
			      of the operator body. */
    ssize_t value;         /* value of a constant or enumerator type,
			      or an offset into the code area
			      (i.e. code address) of the virtual
			      method implementation. Also used for the
			      number of loop counters. */
    const_value_t cvalue;  /* computed value of constant expressions;
			      should replace the above 'value' field
			      in the future. */
    VARTAB *vartab;        /* variables declared in a module */
    VARTAB *consts;        /* constants declared in a module */
    TYPETAB *typetab;      /* types declared in a module */
    VARTAB *operators;     /* operators declared in modules */
    DNODE *module_args;    /* Arguments or parameters of a
                              parametrised module. */

    DNODE *next; /* reference to the next declaration in a declaration
		    list */
    DNODE *prev; /* reference to the previous declaration in a
		    declaration list */
    DNODE *last; /* Last element of the linked list attached to this
                    dnode; can be used for efficient appending of new
                    nodes to the DNODE * list.*/
};

#include <dnode_a.ci>

void deallocate_dnode_buffers( DNODE *dnode )
{
    const_value_free( &dnode->cvalue );
    delete_fixup_list( dnode->code_fixups );
    freex( dnode->name );
    freex( dnode->filename );
    freex( dnode->synonim );
    freex( dnode->code );
}

void delete_dnode( DNODE *node )
{
    DNODE *next;
    while( node ) {
        next = node->next;
	if( node->rcount <= 0 ) {
	    printf( "!!! dnode->rcound == %d (%p) !!!\n",
		    node->rcount, node );
	    assert( node->rcount > 0 );
	}
        if( --node->rcount > 0 )
	    return;

        deallocate_dnode_buffers( node );

	delete_tnode( node->tnode );
	delete_vartab( node->vartab );
	delete_vartab( node->consts );
	delete_typetab( node->typetab );
	delete_vartab( node->operators );
#if 0
	{
	    FIXUP *f;
	    foreach_fixup( f, node->code_fixups ) {
		printf( "dnode 0x%p fixup '%s', addr %d\n",
			node, fixup_name(f), fixup_address(f) );
	    } 
	}
#endif

        delete_dnode( node->module_args );
	free_dnode( node );
	node = next;
    }
}

void dispose_dnode( DNODE *volatile *dnode )
{
    assert( dnode );
    delete_dnode( *dnode );
    *dnode = NULL;
}

void dnode_traverse_rcount2( DNODE *dnode )
{
    if( !dnode ) return;

    dnode->rcount2 ++;

    if( dnode->flags & DF_VISITED ) return;

    dnode->flags |= DF_VISITED;

    tnode_traverse_rcount2( dnode->tnode );

    vartab_traverse_dnodes_and_set_rcount2( dnode->vartab );
    vartab_traverse_dnodes_and_set_rcount2( dnode->consts );
    vartab_traverse_dnodes_and_set_rcount2( dnode->operators );
    typetab_traverse_tnodes_and_set_rcount2( dnode->typetab );
                                        
    dnode_traverse_rcount2( dnode->module_args );
    dnode_traverse_rcount2( dnode->next );
}


void traverse_all_dnodes( void )
{
    DNODE *node;
    for( node = allocated; node != NULL; node = node->next_alloc ) {
        dnode_traverse_rcount2( node );
    }
}

void dnode_mark_accessible( DNODE *dnode )
{
    if( !dnode ) return;

    if( dnode->flags & DF_ACCESSIBLE ) return;

    dnode->flags |= DF_ACCESSIBLE;

    tnode_mark_accessible( dnode->tnode );

    vartab_traverse_dnodes_and_mark_accessible( dnode->vartab );
    vartab_traverse_dnodes_and_mark_accessible( dnode->consts );
    vartab_traverse_dnodes_and_mark_accessible( dnode->operators );
    typetab_traverse_tnodes_and_mark_accessible( dnode->typetab );
                                        
    dnode_mark_accessible( dnode->module_args );
    dnode_mark_accessible( dnode->next );
}

void reset_flags_for_all_dnodes( dnode_flag_t flags )
{
    DNODE *node;
    for( node = allocated; node != NULL; node = node->next_alloc ) {
        dnode_reset_flags( node, flags );
    }
}

void set_accessible_flag_for_all_dnodes( void )
{
    DNODE *node;
    for( node = allocated; node != NULL; node = node->next_alloc ) {
        if( node->rcount > node->rcount2 ) {
            dnode_mark_accessible( node );
        }
    }
}

void set_rcount2_for_all_dnodes( int value )
{
    DNODE *node;
    for( node = allocated; node != NULL; node = node->next_alloc ) {
        node->rcount2 = value;
    }
}

void break_cycles_for_all_dnodes( void )
{
    DNODE *node;
    for( node = allocated; node != NULL; node = node->next_alloc ) {
        dnode_break_cycles( node );
    }
}

void take_ownership_of_all_dnodes( void )
{
    DNODE *node;
    for( node = allocated; node != NULL; node = node->next_alloc ) {
        share_dnode( node );
    }
}

void delete_all_dnodes( void )
{
    DNODE *node, *next;
    for( node = allocated; node != NULL; ) {
        next = node->next_alloc;
        delete_dnode( node );
        node = next;
    }
    //allocated = NULL;
}

DNODE *dnode_break_cycles( DNODE *dnode )
{
    if( dnode ) {
        
        if( (dnode->flags & DF_CYCLES_BROKEN) ||
            (dnode->flags & DF_ACCESSIBLE) )
            return dnode;

        dnode->flags |= DF_CYCLES_BROKEN;

        typetab_break_cycles( dnode->typetab );
        vartab_break_cycles( dnode->vartab );
        vartab_break_cycles( dnode->consts );
        vartab_break_cycles( dnode->operators );

        tnode_break_cycles( dnode->tnode );

        dnode_break_cycles( dnode->next );
        dnode_break_cycles( dnode->module_args );
        
        dispose_tnode( &dnode->tnode );

        dispose_vartab( &dnode->vartab );
        dispose_vartab( &dnode->consts );
        dispose_typetab( &dnode->typetab );
        dispose_vartab( &dnode->operators );
        dispose_fixup_list( &dnode->code_fixups );

        dispose_dnode( &dnode->next );
        dispose_dnode( &dnode->module_args );

        dnode_break_cycles( dnode->next );
    }
    
    return dnode;
}

DNODE *dnode_shallow_copy( DNODE *dst, DNODE *src, cexception_t *ex )
{
    assert( dst );
    assert( src );

    assert( dst != src );

    if( dst->name ) {
        freex( dst->name );
        dst->name = NULL;
    }
    if( src->name )
	dst->name = strdupx( src->name, ex );

    dst->flags = src->flags;

    delete_tnode( dst->tnode );
    dst->tnode = share_tnode( src->tnode );

    if( dst->code ) freex( dst->code );
    dst->code = callocx( sizeof(dst->code[0]), src->code_length, ex );
    memcpy( dst->code, src->code, sizeof(dst->code[0]) * src->code_length );
    dst->code_length = src->code_length;

    /* dst->scope = src->scope; */
    assert( dst->scope == src->scope );
    // dst->offset = src->offset;

    /* rcount is left out */
    /* vartab and typetab are left out, so far. */

    return dst;
}

DNODE* clone_dnode( DNODE *dnode, cexception_t *ex )
{
    DNODE * volatile ret = new_dnode( ex );
    cexception_t inner;

    ret->scope = dnode->scope;

    cexception_guard( inner ) {
        dnode_shallow_copy( ret, dnode, &inner );
    }
    cexception_catch{
        delete_dnode( ret );
        cexception_reraise( inner, ex );
    }

    return ret;
}

DNODE *clone_dnode_list_with_replaced_types( DNODE *dl, TNODE *old, TNODE *new,
                                             cexception_t *ex )
{
    DNODE * volatile newlist = NULL;
    DNODE * volatile newnode = NULL;
    DNODE * curr;
    cexception_t inner;

    cexception_guard( inner ) {
        for( curr = dl; curr != NULL; curr = curr->next ) {
            newnode = clone_dnode( curr, &inner );
            if( dnode_type( newnode ) == old ) {
                dnode_replace_type( newnode, share_tnode( new ));
            }
            newlist = dnode_append( newlist, newnode );
            newnode = NULL;
        }
    }
    cexception_catch{
        delete_dnode( newlist );
        delete_dnode( newnode );
        cexception_reraise( inner, ex );
    }

    return newlist;
}

DNODE* new_dnode( cexception_t *ex )
{
    DNODE *node = alloc_dnode( ex );
    node->rcount = 1;
    return node;
}

DNODE* new_dnode_name( char *name, cexception_t *ex )
{
    cexception_t inner;
    DNODE * volatile ret = new_dnode( ex );

    cexception_guard( inner ) {
        ret->name = strdupx( name, &inner );
    }
    cexception_catch {
        delete_dnode( ret );
	cexception_reraise( inner, ex );
    }
    return ret;
}

DNODE* new_dnode_typed( char *name, TNODE *tnode,
                        cexception_t *ex )
{
    DNODE * volatile ret = new_dnode_name( name, ex );

    ret->tnode = tnode;
    return ret;
}

DNODE* new_dnode_loop( char *name, int ncounters,
                       DNODE *next, cexception_t *ex )
{
    DNODE *dnode = new_dnode_name( name, ex );
    dnode->next = next;
    dnode->value = ncounters;
    return dnode;
}

int dnode_loop_counters( DNODE *dnode )
{
    return dnode ? dnode->value : 0;
}

DNODE *new_dnode_exception( char *exception_name,
			    TNODE *exception_type,
			    cexception_t *ex )
{
    cexception_t inner;
    DNODE * volatile dnode = new_dnode( ex );

    cexception_guard( inner ) {
	dnode->tnode = exception_type;
        dnode->name = strdupx( exception_name, &inner );
    }
    cexception_catch {
        delete_dnode( dnode );
	cexception_reraise( inner, ex );
    }
    return dnode;
}

DNODE* new_dnode_constant( char *name, const_value_t *value, cexception_t *ex )
{
    cexception_t inner;
    DNODE * volatile ret = new_dnode( ex );

    cexception_guard( inner ) {
        ret->name = strdupx( name, &inner );
	if( const_value_type( value ) == VT_INTMAX ) {
            /* for compatibility with older code: */
	    ret->value = value->value.i;
	}
	const_value_move( &ret->cvalue, value );
    }
    cexception_catch {
        delete_dnode( ret );
	cexception_reraise( inner, ex );
    }
    return ret;
}

DNODE *new_dnode_return_value( TNODE *retval_type, cexception_t *ex )
{
    DNODE *node = new_dnode( ex );
    dnode_append_type( node, retval_type );
    return node;
}

typedef TNODE* (*tnode_creator_t) ( char *name,
				    DNODE *volatile *params,
				    DNODE *volatile *retvals,
				    cexception_t *ex );

static DNODE* new_dnode_function_or_operator( char *name,
					      DNODE *volatile *parameters,
					      DNODE *volatile *return_values,
					      tnode_creator_t tnode_creator,
					      cexception_t *ex )
{
    cexception_t inner;
    DNODE * volatile ret = new_dnode_name( name, ex );

    cexception_guard( inner ) {
	ret->tnode = tnode_creator( name, parameters, return_values, &inner );
    }
    cexception_catch {
        delete_dnode( ret );
	cexception_reraise( inner, ex );
    }
    return ret;
}

DNODE* new_dnode_function( char *name,
			   DNODE *volatile *parameters,
			   DNODE *volatile *return_values, 
			   cexception_t *ex )
{
    return new_dnode_function_or_operator( name, parameters, return_values,
					   new_tnode_function_NEW, ex );
}

DNODE* new_dnode_constructor( char *name,
                              DNODE *volatile *parameters,
                              DNODE *volatile *return_values, 
                              cexception_t *ex )
{
    return new_dnode_function_or_operator( name, parameters, return_values,
					   new_tnode_constructor_NEW, ex );
}

DNODE* new_dnode_destructor( char *name,
                             DNODE *volatile *parameters,
                             cexception_t *ex )
{
    DNODE *null_dnode = NULL;
    return new_dnode_function_or_operator( name, parameters,
                                           /* return_values = */ &null_dnode,
					   new_tnode_destructor_NEW, ex );
}

DNODE* new_dnode_method( char *name,
                         DNODE *volatile *parameters,
                         DNODE *volatile *return_values,
                         cexception_t *ex )
{
    return new_dnode_function_or_operator( name, parameters, return_values,
					   new_tnode_method_NEW, ex );
}

DNODE* new_dnode_operator( char *name,
			   DNODE *volatile *parameters,
			   DNODE *volatile *return_values,
			   cexception_t *ex )
{
    cexception_t inner;
    DNODE * volatile op = NULL;

    op = new_dnode_function_or_operator( name, parameters, return_values,
					 new_tnode_operator_NEW, ex );

    cexception_guard( inner ) {
	TNODE *op_type = dnode_type( op );
	if( tnode_is_conversion( op_type )) {
	    DNODE *arg1 = op_type ? tnode_args( op_type ) : NULL;
	    TNODE *arg1_type = arg1 ? dnode_type( arg1 ) : NULL;
	    char *arg1_type_name = arg1_type ? tnode_name( arg1_type ) : NULL;
	    if( arg1 ) {
		freex( op->name );
		op->name = NULL;
		op->name = strdupx( arg1_type_name, &inner );
	    }
	}
    }
    cexception_catch {
	delete_dnode( op );
	cexception_reraise( inner, ex );
    }

    return op;
}

DNODE *new_dnode_module( char *name, cexception_t *ex )
{
    cexception_t inner;
    DNODE *volatile node = new_dnode_name( name, ex );

    cexception_guard( inner ) {
	node->vartab = new_vartab( &inner );
	node->consts = new_vartab( &inner );
	node->typetab = new_typetab( &inner );
	node->operators = new_vartab( &inner );
    }
    cexception_catch {
	delete_dnode( node );
	cexception_reraise( inner, ex );
    }
    return node;
}

DNODE *share_dnode( DNODE* node )
{
    if( node )
        node->rcount ++;
    return node;
}

DNODE *dnode_set_ssize_value( DNODE *dnode, ssize_t val )
{
    assert( dnode );
    dnode->value = val;
    return dnode;
}

ssize_t dnode_ssize_value( DNODE *dnode )
{
    assert( dnode );
    return dnode->value;
}

DNODE *dnode_set_value( DNODE *dnode, const_value_t *val )
{
    assert( dnode );
    if( const_value_type( val ) == VT_INTMAX ) {
        /* for compatibility with older code: */
	dnode->value = val->value.i;
    }
    const_value_move( &dnode->cvalue, val );
    return dnode;
}

const_value_t *dnode_value( DNODE *dnode )
{
    assert( dnode );
    return &dnode->cvalue;
}

DNODE *dnode_set_flags( DNODE *dnode, dnode_flag_t flags )
{
    assert( dnode );
    dnode->flags |= flags;
    return dnode;
}

DNODE *dnode_reset_flags( DNODE *dnode, dnode_flag_t flags )
{
    assert( dnode );
    dnode->flags &= ~flags;
    return dnode;
}

DNODE *dnode_copy_flags( DNODE *dnode, dnode_flag_t flags )
{
    assert( dnode );
    dnode->flags = flags;
    return dnode;
}

int dnode_has_flags( DNODE *dnode, dnode_flag_t flags )
{
    assert( dnode );
    return (dnode->flags & flags);
}

int dnode_has_initialiser( DNODE *dnode )
{
    assert( dnode );
    return (dnode->flags & DF_HAS_INITIALISER);
}

dnode_flag_t dnode_flags( DNODE *dnode )
{
    assert( dnode );
    return dnode->flags;
}

DNODE *dnode_list_set_flags( DNODE *dnode, dnode_flag_t flags )
{
    DNODE *node;
    assert( dnode );

    for( node = dnode; node != NULL; node = node->next ) {
        dnode_set_flags( node, flags );
    }
    return dnode;
}

char *dnode_name( DNODE *dnode ) { assert( dnode ); return dnode->name; }

char *dnode_filename( DNODE *dnode )
{
    assert( dnode );
    return dnode->filename;
}

ssize_t dnode_offset( DNODE *dnode ) { assert( dnode ); return dnode->offset; }

int dnode_scope( DNODE *dnode ) { assert( dnode ); return dnode->scope; }

TNODE *dnode_type( DNODE *dnode ) { return dnode ? dnode->tnode : NULL; }

DNODE *dnode_set_scope( DNODE *dnode, int scope )
{
    assert( dnode );
    dnode->scope = scope;
    return dnode;
}

int dnode_type_is_reference( DNODE *dnode )
{
    if( !dnode || !dnode->tnode ) {
	return 0;
    } else {
	return tnode_is_reference( dnode->tnode );
    }
}

int dnode_type_has_references( DNODE *dnode )
{
    if( !dnode || !dnode->tnode ) {
	return 0;
    } else {
	return tnode_has_references( dnode->tnode );
    }
}

int dnode_is_function_prototype( DNODE *dnode )
{
    if( !dnode ) {
	return 0;
    } else {
	return dnode_has_flags( dnode, DF_FNPROTO );
    }
}

int dnode_function_prototypes_match_msg( DNODE *d1, DNODE *d2,
					 char *msg, int msglen )
{
    TNODE *t1 = dnode_type( d1 );
    TNODE *t2 = dnode_type( d2 );

    return tnode_function_prototypes_match_msg( t1, t2, msg, msglen );
}

int dnode_list_length( DNODE *dnode )
{
    int len = 0;

    while( dnode ) {
	len++;
	dnode = dnode->next;
    }
    return len;
}

DNODE *dnode_list_lookup( DNODE *dnode_list, const char *name )
{
    DNODE *dnode;

    if( !name ) return NULL;

    for( dnode = dnode_list; dnode != NULL; dnode = dnode->next ) {
        if( strcmp( name, dnode->name ) == 0 ) {
	    return dnode;
	}
    }
    return NULL;
}

DNODE *dnode_list_lookup_arity( DNODE *dnode_list,
				const char *name,
				int arity )
{
    DNODE *dnode;

    if( !name ) return NULL;

    for( dnode = dnode_list; dnode != NULL; dnode = dnode->next ) {
	TNODE *current_type = dnode_type( dnode );
	DNODE *dnode_args = current_type ? tnode_args( current_type ) : NULL;
	int current_arity = dnode_args ? dnode_list_length( dnode_args ) : 0;
        if( strcmp( name, dnode->name ) == 0 &&
	    current_arity == arity ) {
	    return dnode;
	}
    }
    return NULL;
}

#if 0
DNODE *dnode_list_lookup_compatible( DNODE *dnode_list,
				     DNODE *target )
{
    DNODE *dnode;
    TNODE *target_type;
    const char *target_name;

    assert( target );

    target_name = dnode_name( target );
    target_type = dnode_type( target );

    for( dnode = dnode_list; dnode != NULL; dnode = dnode->next ) {
	TNODE *current_type = dnode_type( dnode );
        if( strcmp( target_name, dnode->name ) == 0 &&
	    target_type && current_type &&
	    tnode_types_are_compatible( target_type, current_type )) {
	    break;
	}
    }
    return dnode;
}
#endif

DNODE *dnode_list_lookup_proto_by_tnodes( DNODE *dnode_list,
					  char *name,
					  int arity,
					  ... )
{
    DNODE *dnode;
    va_list ap;

    for( dnode = dnode_list; dnode != NULL; dnode = dnode->next ) {
        if( strcmp( name, dnode->name ) == 0 ) {
	    TNODE *dnode_tnode = dnode_type( dnode );
	    DNODE *arg_list = dnode_tnode ? tnode_args( dnode_tnode ) : NULL;
	    int arg_length = dnode_list_length( arg_list );

	    if( arg_length == arity ) {
		int matches = 1;
		DNODE *arg;
		va_start( ap, arity );
		foreach_dnode( arg, arg_list ) {
		    TNODE *arg_type = dnode_type( arg );
		    TNODE *req_type = va_arg( ap, TNODE* );
		    if( !tnode_types_are_compatible( req_type, arg_type,
						     NULL /* generic_types */,
						     NULL /* ex */ )) {
			matches = 0;
			break;
		    }
		}
		va_end( ap );
		if( matches )
		    break;
	    }
	}
    }
    return dnode;
}

int dnode_lists_are_type_compatible( DNODE *l1, DNODE *l2,
				     TYPETAB *generic_types,
				     cexception_t *ex )
{
    DNODE *l1_curr;
    DNODE *l2_curr = l2;

    foreach_dnode( l1_curr, l1 ) {
	TNODE *l1_type, *l2_type;

	if( !l1_curr || !l2_curr ) {
	    return 0;
	}

	l1_type = dnode_type( l1_curr );
	l2_type = dnode_type( l2_curr );
	if( !l1_type || !l2_type ||
	    !tnode_types_are_compatible( l1_type, l2_type,
					 generic_types, ex )) {
	    return 0;
	} else {
	    l2_curr = dnode_next( l2_curr );
	}
    }

    if( !l1_curr && !l2_curr ) {
	return 1;
    } else {
	return 0;
    }
}

int dnode_lists_are_type_identical( DNODE *l1, DNODE *l2,
				    TYPETAB *generic_types,
				    cexception_t *ex )
{
    DNODE *l1_curr;
    DNODE *l2_curr = l2;

    foreach_dnode( l1_curr, l1 ) {
	TNODE *l1_type, *l2_type;

	if( !l1_curr || !l2_curr ) {
	    return 0;
	}

	l1_type = dnode_type( l1_curr );
	l2_type = dnode_type( l2_curr );
	if( !l1_type || !l2_type ||
	    !tnode_types_are_identical( l1_type, l2_type,
					generic_types, ex )) {
	    return 0;
	} else {
	    l2_curr = dnode_next( l2_curr );
	}
    }

    if( !l1_curr && !l2_curr ) {
	return 1;
    } else {
	return 0;
    }
}

/* append dnode list tail to the end of the dnode list head */

DNODE* dnode_append( DNODE *head, DNODE *tail )
{
    DNODE *last;
    if( !head ) {
        return tail;
    } else {
        last = head->last ? head->last : head;
        while( last->next ) {
	    last = last->next;
	}
	last->next = tail;
	if( tail ) {
	    tail->prev = last;
	}
        head->last = tail && tail->last ? tail->last : tail;
	return head;
    }
}

DNODE *dnode_disconnect( DNODE *dnode )
{
    assert( dnode );
    if( dnode->next ) {
	dnode->next->prev = NULL;
	dnode->next = NULL;
        dnode->last = NULL;
    }
    return dnode;
}

DNODE *dnode_next( DNODE *dnode )
{
    assert( dnode );
    return dnode->next;
}

DNODE *dnode_prev( DNODE *dnode )
{
    assert( dnode );
    return dnode->prev;
}

DNODE *dnode_list_last( DNODE *dnode )
{
    if( !dnode ) {
	return NULL;
    } else {
        if( dnode->last )
            dnode = dnode->last;
	while( dnode->next ) {
	    dnode = dnode->next;
	}
	return dnode;
    }
}

DNODE *dnode_module_args( DNODE *dnode )
{
    assert( dnode );
    return dnode->module_args;
}

DNODE *dnode_insert_module_args( DNODE *dnode, DNODE *volatile *args )
{
    assert( dnode );
    assert( args );
    dnode->module_args = *args;
    *args = NULL;
    return dnode;
}

void dnode_assign_offset( DNODE *dnode, ssize_t *offset )
{
    int delta;
    ssize_t stackcells;

    assert( offset );
    assert( dnode );

    delta = *offset > 0 ? +1 : -1;
    stackcells = 1; /* size of variable in stackcells */
    *offset += delta * stackcells;
    dnode->offset = *offset - delta;
}

void dnode_list_assign_offsets( DNODE *dnode_list, ssize_t *offset )
{
    DNODE *dnode;

    assert( offset );
    for( dnode = dnode_list; dnode != NULL; dnode = dnode->next ) {
        dnode_assign_offset( dnode, offset );
    }
}

DNODE *dnode_set_offset( DNODE *dnode, ssize_t offset )
{
    assert( dnode );
#if 0
    assert( dnode->offset == 0 ||
            (dnode_type(dnode) && tnode_kind(dnode_type(dnode)) == TK_METHOD) );
#endif
    dnode->offset = offset;
    dnode_set_flags( dnode, DF_HAS_OFFSET );
    return dnode;
}

DNODE *dnode_update_offset( DNODE *dnode, ssize_t offset )
{
    assert( dnode );
    dnode->offset = offset;
    return dnode;
}

DNODE *dnode_set_name( DNODE *dnode, char *name, cexception_t *ex )
{
    assert( dnode );
    assert( !dnode->name );
    dnode->name = strdupx( name, ex );
    return dnode;
}

DNODE *dnode_set_filename( DNODE *dnode, char *filename, cexception_t *ex )
{
    assert( dnode );
    assert( !dnode->filename );
    dnode->filename = strdupx( filename, ex );
    return dnode;
}

DNODE *dnode_set_synonim( DNODE *dnode, char *synonim, cexception_t *ex )
{
    assert( dnode );
    assert( !dnode->synonim );
    dnode->synonim = strdupx( synonim, ex );
    return dnode;
}

DNODE *dnode_insert_synonim( DNODE *dnode, char *volatile *synonim )
{
    assert( dnode );
    assert( synonim );
    assert( !dnode->synonim );
    dnode->synonim = *synonim;
    *synonim = NULL;
    return dnode;
}

char *dnode_synonim( DNODE *dnode )
{
    assert( dnode );
    return dnode->synonim;
}

DNODE *dnode_append_type( DNODE *dnode, TNODE *tnode )
{
    TNODE *true_tnode = NULL;
    assert( dnode );

#if 0
    if( tnode && tnode_kind( tnode ) == TK_DERIVED ) {
	true_tnode = tnode_base_type( tnode );
    } else {
	true_tnode = tnode;
    }
#else
    true_tnode = tnode;
#endif

    dnode->tnode = tnode_append_element_type( dnode->tnode, true_tnode );
    return dnode;
}

DNODE *dnode_list_append_type( DNODE *dnode, TNODE *tnode )
{
    DNODE *node;
    assert( dnode );

    dnode_append_type( dnode, tnode );
    for( node = dnode->next; node != NULL; node = node->next ) {
        dnode_append_type( node, share_tnode( tnode ));
    }
    return dnode;
}

DNODE *dnode_insert_type( DNODE *dnode, TNODE *tnode )
{
    assert( dnode );
    assert( tnode_next(tnode) == NULL );

    dnode->tnode = tnode_insert_element_type( tnode, dnode->tnode );

    return dnode;
}

DNODE *dnode_list_insert_type( DNODE *dnode, TNODE *tnode )
{
    DNODE *node;
    assert( dnode );

    dnode_insert_type( dnode, tnode );
    for( node = dnode->next; node != NULL; node = node->next ) {
        dnode_insert_type( node, share_tnode( tnode ));
    }
    return dnode;
}

DNODE *dnode_replace_type( DNODE *dnode, TNODE *tnode )
{
    assert( dnode );
    assert( tnode_next(tnode) == NULL );

    if( dnode->tnode ) {
	delete_tnode( dnode->tnode );
    }
    dnode->tnode = tnode;

    return dnode;
}

DNODE *dnode_function_args( DNODE *dnode )
{
    return tnode_args( dnode->tnode );
}

DNODE *dnode_insert_code_fixup( DNODE *dnode, FIXUP *fixup )
{
    assert( dnode );
    assert( fixup );
    assert( fixup_next( fixup ) == NULL );

    dnode->code_fixups = fixup_append( fixup, dnode->code_fixups );

    return dnode;
}

DNODE *dnode_adjust_code_fixups( DNODE *dnode, ssize_t address )
{
    assert( dnode );

    fixup_list_adjust_addresses( dnode->code_fixups, address );

    return dnode;
}

FIXUP *dnode_code_fixups( DNODE *dnode )
{
    assert( dnode );
    return dnode->code_fixups;
}

DNODE *dnode_set_code( DNODE *dnode, thrcode_t *code,
		       ssize_t code_length,
		       cexception_t *ex )
{
    assert( dnode );

    if( dnode->code ) {
	freex( dnode->code );
	dnode->code = NULL;
	dnode->code_length = 0;
    }

    if( code ) {
	dnode->code = callocx( sizeof(code[0]), code_length, ex );
	memmove( dnode->code, code, sizeof(code[0]) * code_length );
	dnode->code_length = code_length;
    }

    return dnode;
}

thrcode_t *dnode_code( DNODE *dnode, ssize_t *code_length )
{
    assert( dnode );
    if( code_length ) {
	*code_length = dnode->code_length;
    }
    return dnode->code;
}

VARTAB *dnode_vartab( DNODE *dnode )
{
    assert( dnode );
    return dnode->vartab;
}

VARTAB *dnode_constants_vartab( DNODE *dnode )
{
    assert( dnode );
    return dnode->consts;
}

VARTAB *dnode_operator_vartab( DNODE *dnode )
{
    assert( dnode );
    return dnode->operators;
}

TYPETAB *dnode_typetab( DNODE *dnode )
{
    assert( dnode );
    return dnode->typetab;
}

void dnode_vartab_insert_dnode( DNODE *dnode, const char *name,
                                DNODE *volatile *var,
				cexception_t *ex )
{
    assert( var );
    assert( dnode->vartab );
    vartab_insert( dnode->vartab, name, var, ex );
}

void dnode_vartab_insert_named_dnode( DNODE *dnode, DNODE *volatile *var,
				      cexception_t *ex )
{
    assert( var );
    assert( dnode->vartab );
    vartab_insert_named( dnode->vartab, var, ex );
}

void dnode_vartab_insert_named_vars( DNODE *dnode, DNODE *volatile *vars,
				     cexception_t *ex )
{
    assert( vars );
    assert( dnode->vartab );
    vartab_insert_named_vars( dnode->vartab, vars, ex );
}

void dnode_optab_insert_named_operator( DNODE *dnode,
                                        DNODE *volatile *operator,
                                        cexception_t *ex )
{
    assert( operator );
    assert( dnode->vartab );
    vartab_insert_named_operator( dnode->operators, operator, ex );
}

void dnode_optab_insert_operator( DNODE *dnode, char *opname,
                                  DNODE *volatile *operator,
                                  cexception_t *ex )
{
    assert( operator );
    assert( dnode->vartab );
    vartab_insert_operator( dnode->operators, opname, operator, ex );
}

DNODE *dnode_vartab_lookup_var( DNODE *dnode, const char *name )
{
    assert( dnode );
    assert( dnode->vartab );
    return vartab_lookup( dnode->vartab, name );
}

void dnode_consttab_insert_consts( DNODE *dnode,
                                   DNODE *volatile *vars,
				   cexception_t *ex )
{
    assert( vars );
    assert( dnode->consts );
    vartab_insert_named_vars( dnode->consts, vars, ex );
}

DNODE *dnode_consttab_lookup_const( DNODE *dnode, const char *name )
{
    assert( dnode->consts );
    return vartab_lookup( dnode->consts, name );
}

void dnode_typetab_insert_tnode( DNODE *dnode, const char *name, TNODE *tnode, 
				 cexception_t *ex )
{
    assert( dnode->typetab );
    typetab_insert( dnode->typetab, name, &tnode, ex );
}

void dnode_typetab_insert_tnode_suffix( DNODE *dnode,
					const char *suffix_name,
					type_suffix_t suffix_type, 
					TNODE *tnode, 
					cexception_t *ex )
{
    assert( dnode->typetab );
    typetab_insert_suffix( dnode->typetab, suffix_name, suffix_type, &tnode,
                           /* count = */ NULL,
                           /* is_imported = */ NULL,
                           ex );
}

void dnode_typetab_insert_named_tnode( DNODE *dnode, TNODE *tnode,
				       cexception_t *ex )
{
    assert( dnode->typetab );
    typetab_insert( dnode->typetab, tnode_name(tnode), &tnode, ex );
}

TNODE *dnode_typetab_lookup_type( DNODE *dnode, const char *name )
{
    assert( dnode->typetab );
    return typetab_lookup( dnode->typetab, name );
}

TNODE *dnode_typetab_lookup_suffix( DNODE *dnode, const char *name,
				    type_suffix_t suffix )
{
    assert( dnode->typetab );
    return typetab_lookup_suffix( dnode->typetab, name, suffix );
}

int dnode_module_args_are_identical( DNODE *m1, DNODE *m2, SYMTAB *symtab )
{
    DNODE *arg1, *arg2;
    TYPETAB *ttab = symtab ? symtab_typetab( symtab ) : NULL;

#if 1
    if( !ttab ) {
        if( m1->module_args )
            return 0;
        else
            return 1;
    }
#endif

#if 0
    printf( "\n" );
#endif

    arg2 = m2->module_args;

    foreach_dnode( arg1, m1->module_args ) {
        TNODE *arg1_type = dnode_type( arg1 );
        // printf( ">>>> parameter '%s' (type kind = %s), argument '%s'\n",
        //         dnode_name( arg ), tnode_kind_name( param_type ),
        //         dnode_name( param ));
        char *argument_name;
        if( !arg2 ) {
            argument_name = dnode_synonim( arg1 );
            if( !argument_name )
                return 0;
        } else {
            argument_name = dnode_name( arg2 );
        }
        if( tnode_kind( arg1_type ) == TK_TYPE ) {
            /* Prevent assertions from failing if the argument name is
               not given -- such things can happen if numeric constant
               is passed instead of a named module parameter (in this
               branch, instead of a type): */
            if( !argument_name )
                return 0;
            TNODE *arg2_type = ttab ?
                typetab_lookup( ttab, argument_name ) :
                tnode_base_type( dnode_type( arg2 ));
            // printf( ">>> found type '%s'\n", tnode_name( arg_type ) );
#if 0
            printf( ">>> typtab is %p\n", ttab );
            printf( ">>> checking types for identity: "
                    "arg1 = %p '%s' (type = '%s', base = '%s'), "
                    "arg2 = %p '%s' (type = '%s')\n",
                    arg1 ? tnode_base_type( dnode_type( arg1 )) : NULL,
                    dnode_name( arg1 ),
                    arg1 ? tnode_kind_name( dnode_type( arg1 )) : "?",
                    arg1 ? tnode_name( tnode_base_type( dnode_type( arg1 ))) : "?",
                    arg2_type, argument_name,
                    arg2_type ? tnode_name( arg2_type ) : "?"
                    );
#endif
            if( !tnode_types_are_identical
                ( tnode_base_type( dnode_type( arg1 )),
                  arg2_type,
                  NULL, NULL ) ) {
                // printf( ">>> NOT identical\n" );
                return 0;
            }
        } else if( tnode_kind( arg1_type ) == TK_CONST ) {
            VARTAB *ctab = symtab_consttab( symtab );
            DNODE *arg2_const = vartab_lookup( ctab, argument_name );
#if 0
            printf( ">>> checking constant for identity: "
                    "arg1 = '%s' (module arg: '%s'), arg2 = '%s' "
                    "(found as '%s')\n",
                    dnode_name( arg1 ),
                    dnode_name( dnode_module_args( arg1 )),
                    argument_name,
                    arg2_const ? dnode_name( arg2_const ) : "?"
                    );
#endif
            if( arg2_const != dnode_module_args( arg1 ) ) {
                return 0;
            }
        } else if( tnode_kind( arg1_type ) == TK_VAR ||
                   tnode_kind( arg1_type ) == TK_FUNCTION ) {
            VARTAB *vtab = symtab_vartab( symtab );
            DNODE *arg2_dnode = vartab_lookup( vtab, argument_name );
#if 0
            printf( ">>> checking variables or functions for identity: "
                    "arg1 = '%s' (module arg: '%s'), arg2 = '%s' "
                    "(found as '%s')\n",
                    dnode_name( arg1 ),
                    dnode_name( dnode_module_args( arg1 )),
                    argument_name,
                    dnode_name( arg2_dnode )
                    );
#endif
            if( arg2_dnode != dnode_module_args( arg1 ) ) {
                return 0;
            }
        } else {
            yyerrorf( "sorry, parameters of kind '%s' are not yet "
                      "supported for modules", 
                      tnode_kind_name( arg1_type ));
            return 0;
        }

        if( arg2 )
            arg2 = arg2->next;
    }

    return 1;
}

DNODE *dnode_remove_last( DNODE *list )
{
    DNODE *last_arg;

    assert( list );

    last_arg = list->last ? list->last : list;
    while( last_arg->next ) {
        last_arg = last_arg->next;
    }
    last_arg->prev->next = NULL;
    list->last = last_arg->prev;
    delete_dnode( last_arg );
    for( last_arg = list->next; last_arg; last_arg = last_arg->next ) {
        last_arg->last = list->last;
    }
    return list;
}
