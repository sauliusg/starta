/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* tnode -- representation of the type definition parse tree */
/* tnode tree is built by the parser (grammar.y) */
/* from this tnode tree a type symbol table is built */

/* exports: */
#include <tnode.h>

/* uses: */
#include <string.h> /* for memset() */
#include <limits.h> /* for CHAR_BIT */
#include <alloccell.h>
#include <stackcell.h>
#include <tcodes.h>
#include <tlist.h>
#include <allocx.h>
#include <stringx.h>
#include <assert.h>
#include <yy.h>

#include <tnode.ci>
#include <tnode_a.ci>

void delete_tnode( TNODE *tnode )
{
    if( tnode ) {
        if( tnode->rcount <= 0 ) {
	    printf( "!!! tnode->rcount = %ld (%s) !!!\n",
		    tnode->rcount, tnode_kind_name(tnode) );
	    assert( tnode->rcount > 0 );
	}
        if( --tnode->rcount > 0 )
	    return;
        freex( tnode->name );
        freex( tnode->suffix );
	delete_dnode( tnode->fields );
	delete_dnode( tnode->operators );
	delete_dnode( tnode->conversions );
	delete_dnode( tnode->methods );
	delete_dnode( tnode->args );
	delete_dnode( tnode->return_vals );
	delete_tnode( tnode->base_type );
	delete_tnode( tnode->element_type );
        delete_tlist( tnode->interfaces );
	delete_dnode( tnode->constructor );
	delete_dnode( tnode->destructor );
	delete_tnode( tnode->next );
	free_tnode( tnode );
    }
}

static void tnode_update_self_parameter_type( TNODE *new_tnode,
					      TNODE *old_tnode )
{
    DNODE *method;

    foreach_dnode( method, new_tnode->methods ) {
	TNODE *method_type = dnode_type( method );
	DNODE *parameters = method_type ? tnode_args( method_type ) : NULL;
	DNODE *parameter;

	foreach_dnode( parameter, parameters ) {
	    if( strcmp( dnode_name( parameter ), "self" ) == 0 ) {
		assert( dnode_type( parameter ) == old_tnode );
		dnode_replace_type( parameter, share_tnode( new_tnode ));
	    }
	}
    }
}

TNODE *tnode_shallow_copy( TNODE *dst, TNODE *src )
{
    int dst_rcount, src_rcount;
    TNODE *dst_element = NULL;
    type_kind_t dst_kind;

    if( dst == src ) return dst;

    assert( dst );
    assert( src );

    if( dst->name ) freex( dst->name );
    if( dst->suffix ) freex( dst->suffix );
    dst->name = NULL;
    dst->suffix = NULL;

    assert( dst->flags & TF_IS_FORWARD );

    dst_rcount = dst->rcount;
    src_rcount = src->rcount;
    dst_element = dst->element_type;
    /* The field dst->base_type is simply copied along with all other
       fields. */
    dst_kind = dst->kind;
    *dst = *src;
    memset( src, 0, sizeof(*src));
    dst->rcount = dst_rcount;
    src->rcount = src_rcount;

    assert( dst->base_type != dst );

    if( dst_kind == TK_COMPOSITE ) {
	assert( !dst->element_type );
	dst->element_type = dst_element;
	dst->kind = dst_kind;
    }

    tnode_update_self_parameter_type( dst, src );

    return dst;
}

TNODE *tnode_convert_to_element_type( TNODE *tnode )
{
    TNODE *element_type;

    assert( tnode );
    element_type = tnode_element_type( tnode );
    share_tnode( element_type );
    delete_tnode( tnode );
    return element_type;
}

TNODE *share_tnode( TNODE* node )
{
    if( !node ) return NULL;
    node->rcount ++;
    return node;
}

TNODE *new_tnode( cexception_t *ex )
{
    TNODE *tnode = alloc_tnode( ex );
    tnode->rcount = 1;
   return tnode;
}

TNODE *new_tnode_forward( char *name, cexception_t *ex )
{
    cexception_t inner;
    TNODE * volatile node = new_tnode( ex );

    assert( name );
    cexception_guard( inner ) {
	node->name = strdupx( name, &inner );
	node->kind = TK_NONE;
	tnode_set_flags( node, TF_IS_FORWARD );
    }
    cexception_catch {
        delete_tnode( node );
        cexception_reraise( inner, ex );
    }
    return node;
}

TNODE *new_tnode_forward_struct( char *name, cexception_t *ex )
{
    cexception_t inner;
    TNODE * volatile node = new_tnode( ex );

    cexception_guard( inner ) {
        if( name )
            node->name = strdupx( name, &inner );
	node->kind = TK_STRUCT;
	tnode_set_flags( node, TF_IS_FORWARD | TF_IS_REF );
    }
    cexception_catch {
        delete_tnode( node );
        cexception_reraise( inner, ex );
    }
    return node;
}

TNODE *new_tnode_forward_class( char *name, cexception_t *ex )
{
    cexception_t inner;
    TNODE * volatile node = new_tnode( ex );

    cexception_guard( inner ) {
        if( name )
            node->name = strdupx( name, &inner );
	node->kind = TK_CLASS;
	tnode_set_flags( node, TF_IS_FORWARD | TF_IS_REF );
    }
    cexception_catch {
        delete_tnode( node );
        cexception_reraise( inner, ex );
    }
    return node;
}

TNODE *new_tnode_forward_interface( char *name, cexception_t *ex )
{
    cexception_t inner;
    TNODE * volatile node = new_tnode( ex );

    assert( name );
    cexception_guard( inner ) {
	node->name = strdupx( name, &inner );
	node->kind = TK_INTERFACE;
	tnode_set_flags( node, TF_IS_REF );
    }
    cexception_catch {
        delete_tnode( node );
        cexception_reraise( inner, ex );
    }
    return node;
}

TNODE *new_tnode_ptr( cexception_t *ex )
{
    TNODE * volatile node = new_tnode( ex );

    node->kind = TK_REF;
    tnode_set_flags( node, TF_IS_REF );
    return node;
}

TNODE *new_tnode_nullref( cexception_t *ex )
{
    TNODE * volatile node = new_tnode( ex );

    node->kind = TK_NULLREF;
    tnode_set_flags( node, TF_IS_REF );
    return node;
}

#if 0
TNODE *new_tnode_any( cexception_t *ex )
{
    TNODE * volatile node = new_tnode( ex );

    node->kind = TK_ANY;
    return node;
}
#endif

TNODE *new_tnode_ignored( cexception_t *ex )
{
    TNODE * volatile node = new_tnode( ex );

    node->kind = TK_IGNORE;
    return node;
}

TNODE *new_tnode_ref( cexception_t *ex )
{
    TNODE * volatile node = new_tnode( ex );

    node->kind = TK_REF;
    tnode_set_flags( node, TF_IS_REF );
    return node;
}

TNODE *new_tnode_derived( TNODE *base, cexception_t *ex )
{
    cexception_t inner;
    TNODE *node = new_tnode( ex );

    cexception_guard( inner ) {
	/* node->kind = base->kind; */
	node->kind = TK_DERIVED;
	/* base->name is not copied */
#if 0
	while( base && base->kind == TK_DERIVED &&
               tnode_has_flags( base, TF_IS_EQUIVALENT ))
	    base = base->base_type;
#endif
	assert( node != base );
	node->base_type = share_tnode( base );
	if( base ) {
	    node->element_type = share_tnode( base->element_type );
	    node->size = base->size;
	    node->nrefs = base->nrefs;
	    /* base->rcount is skipped, of cource ;-) */
	    node->fields = share_dnode( base->fields );
	    node->flags = base->flags;
#if 0
	    node->operators = share_dnode( base->operators );
	    node->conversions = share_dnode( base->conversions );
#endif
	    node->args = share_dnode( base->args );
	    node->return_vals = share_dnode( base->return_vals );
	}
	node->flags &= ~TF_IS_FORWARD;
    }
    cexception_catch {
	delete_tnode( node );
	cexception_reraise( inner, ex );
    }
    return node;
}

TNODE *new_tnode_equivalent( TNODE *base, cexception_t *ex )
{
    TNODE *node = new_tnode_derived( base, ex );
    node->flags |= TF_IS_EQUIVALENT;
    return node;
}

TNODE *new_tnode_blob( TNODE *base_type,
                       cexception_t *ex )
{
    cexception_t inner;
    TNODE * volatile node = new_tnode( ex );

    cexception_guard( inner ) {
	node->kind = TK_BLOB;
	node->size = 1;
        node->base_type = base_type;
	tnode_set_flags( node, TF_IS_REF );
    }
    cexception_catch {
        delete_tnode( node );
        cexception_reraise( inner, ex );
    }
    return node;
}

TNODE *copy_unnamed_tnode( TNODE *tnode, cexception_t *ex )
{
    cexception_t inner;
    TNODE *copy = new_tnode( ex );

    cexception_guard( inner ) {
	assert( tnode );
        copy->kind = tnode->kind;
	copy->flags = tnode->flags;
        /* tnode->name is not copied */
        copy->element_type = share_tnode( tnode->element_type );
        copy->size = tnode->size;
        copy->nrefs = tnode->nrefs;
        /* tnode->rcount is skipped, of cource ;-) */
        copy->fields = share_dnode( tnode->fields );
        copy->flags = tnode->flags;
        copy->operators = share_dnode( tnode->operators );
        copy->conversions = share_dnode( tnode->conversions );
        copy->args = share_dnode( tnode->args );
        copy->return_vals = share_dnode( tnode->return_vals );
    }
    cexception_catch {
	delete_tnode( copy );
	cexception_reraise( inner, ex );
    }
    return copy;
}

TNODE * tnode_set_nref( TNODE *tnode, ssize_t nref )
{
    assert( tnode );
    /* assert( tnode->nrefs == 0 || tnode->nrefs == nref ); */
    tnode->nrefs = nref;
    if( nref > 0 )
	tnode_set_has_references( tnode );
    return tnode;
}

TNODE *new_tnode_array( TNODE *element_type,
			TNODE *base_type,
			cexception_t *ex )
{
    TNODE * volatile tnode = new_tnode( ex );

    tnode->kind = TK_ARRAY;
    tnode->element_type = element_type;
    assert( tnode != base_type );
    tnode->base_type = base_type;
    tnode->flags |= TF_IS_REF;

    return tnode;
}

TNODE *new_tnode_addressof( TNODE *element_type, cexception_t *ex )
{
    TNODE * volatile tnode = new_tnode( ex );

    tnode->kind = TK_ADDRESSOF;
    tnode->element_type = element_type;
    tnode->size = 0;
    return tnode;
}

TNODE *new_tnode_function_or_proc_ref( DNODE *parameters,
				       DNODE *return_dnodes,
				       TNODE *base_type,
				       cexception_t *ex )
{
    cexception_t inner;
    TNODE * volatile tnode = new_tnode( ex );

    cexception_guard( inner ) {
	tnode->kind = TK_FUNCTION_REF;
	tnode->size = REF_SIZE;
	assert( tnode != base_type );
	tnode->base_type = base_type;
	tnode->args = parameters;
	tnode->return_vals = return_dnodes;
	tnode_set_flags( tnode, TF_IS_REF );
	if( return_dnodes ) {
	    tnode->element_type = share_tnode( dnode_type( return_dnodes ));
	}
    }
    cexception_catch {
	delete_tnode( tnode );
	cexception_reraise( inner, ex );
    }
    return tnode;
}

static TNODE *new_tnode_function_or_operator( char *name,
					      DNODE *parameters,
					      DNODE *return_dnodes,
					      type_kind_t kind,
					      cexception_t *ex )
{
    cexception_t inner;
    TNODE * volatile tnode = new_tnode( ex );

    cexception_guard( inner ) {
	tnode->kind = kind;
	tnode->size = REF_SIZE; /* in assignments, functions and
				   procedures are represented by
				   addresses, thus having size of
				   REF_SIZE */
	tnode_set_flags( tnode, TF_IS_REF );
	tnode->args = parameters;
	tnode->return_vals = return_dnodes;
	if( return_dnodes ) {
	    tnode->element_type = share_tnode( dnode_type( return_dnodes ));
	}
	if( name ) {
	    tnode->name = strdupx( name, &inner );
	} else {
	    tnode->name = strdupx( "--null function name--", &inner );
	}
    }
    cexception_catch {
	delete_tnode( tnode );
	cexception_reraise( inner, ex );
    }
    return tnode;
}

TNODE *new_tnode_function( char *name,
			   DNODE *parameters,
			   DNODE *return_dnodes,
			   cexception_t *ex )
{
    return new_tnode_function_or_operator( name, parameters, return_dnodes,
					   TK_FUNCTION, ex );
}

TNODE *new_tnode_constructor( char *name,
                              DNODE *parameters,
                              DNODE *return_dnodes,
                              cexception_t *ex )
{
    return new_tnode_function_or_operator( name, parameters, return_dnodes,
					   TK_CONSTRUCTOR, ex );
}

TNODE *new_tnode_destructor( char *name,
                             DNODE *parameters,
                             DNODE *return_dnodes,
                             cexception_t *ex )
{
    return new_tnode_function_or_operator( name, parameters, return_dnodes,
					   TK_DESTRUCTOR, ex );
}

TNODE *new_tnode_method( char *name,
                         DNODE *parameters,
                         DNODE *return_dnodes,
                         cexception_t *ex )
{
    return new_tnode_function_or_operator( name, parameters, return_dnodes,
					   TK_METHOD, ex );
}

TNODE *new_tnode_operator( char *name,
			   DNODE *parameters,
			   DNODE *return_dnodes,
			   cexception_t *ex )
{
    return new_tnode_function_or_operator( name, parameters, return_dnodes,
					   TK_OPERATOR, ex );
}

static int tnode_is_constructor( TNODE *tnode )
{
    return tnode && tnode->kind == TK_CONSTRUCTOR;
}

static int tnode_is_destructor( TNODE *tnode )
{
    return tnode && tnode->kind == TK_DESTRUCTOR;
}

static int tnode_is_method( TNODE *tnode )
{
    return tnode && tnode->kind == TK_METHOD;
}

static int tnode_is_operator( TNODE *tnode )
{
    return tnode && tnode->kind == TK_OPERATOR;
}

int tnode_is_conversion( TNODE *tnode )
{
    char *name = tnode ? tnode_name( tnode ) : NULL;
    int l = name ? strlen( name ) : 0;

    return tnode && tnode->kind == TK_OPERATOR &&
	dnode_list_length( tnode->args ) == 1 &&
	l >= 1 && name[0] == '@';
}

int tnode_is_forward( TNODE *tnode )
{
    return (tnode->flags & TF_IS_FORWARD) != 0;
}

int tnode_is_extendable_enum( TNODE *tnode )
{
    return (tnode->flags & TF_EXTENDABLE_ENUM) != 0;
}

int tnode_is_array_of_string( TNODE *tnode )
{
    TNODE *element_type;

    element_type = tnode ? tnode_element_type( tnode ) : NULL;

    return
	tnode && tnode_kind( tnode ) == TK_ARRAY &&
	element_type && tnode_kind( element_type ) == TK_STRING;
}

int tnode_is_array_of_file( TNODE *tnode )
{
    TNODE *element_type;
    char *name;

    element_type = tnode ? tnode_element_type( tnode ) : NULL;
    name = element_type ? tnode_name( element_type ) : NULL;

    return
	tnode && tnode_kind( tnode ) == TK_ARRAY &&
	/* base && tnode_kind( base ) == TK_FILE; */
	name && strcmp( name, "file" ) == 0;
}

int tnode_is_immutable( TNODE *tnode )
{
    assert( tnode );
    return tnode->flags & TF_IS_IMMUTABLE;
}

static void yyerrorf_defined_field( TNODE *tnode, char *item_name,
                                    DNODE *field )
{
    if( tnode_name( tnode )) {
        yyerrorf( "%s '%s' already defined in type '%s'",
                  item_name, dnode_name( field ), tnode_name( tnode ));
    } else {
        yyerrorf( "%s '%s' already defined in the current type",
                  item_name, dnode_name( field ));
    }
}

static void tnode_check_field_does_not_exist( TNODE *tnode,
					      DNODE *field_list,
					      char *item_name,
					      DNODE *field )
{
    if( dnode_list_lookup( field_list, dnode_name( field ))) {
        yyerrorf_defined_field( tnode, item_name, field );
    }
}

static DNODE* tnode_check_method_does_not_exist( TNODE *tnode,
                                                 DNODE *field_list,
                                                 DNODE *field )
{
    DNODE *existing_method;

    assert( field );

    if( (existing_method =
         dnode_list_lookup( field_list, dnode_name( field ))) != NULL ) {

        if( (!dnode_is_function_prototype( existing_method ) ||
             dnode_is_function_prototype( field )) &&
            existing_method != field ) {
            if( dnode_is_function_prototype( existing_method )) {
                yyerrorf_defined_field( tnode, "forward method", field );
            } else {
                yyerrorf_defined_field( tnode, "method", field );
            }
        }
    }

    return existing_method;
}

static char *arity_name( int arity )
{
    static char pad[20];

    if( arity > 0 ) {
	switch( arity ) {
	    case 1: return "unary "; break;
	    case 2: return "binary "; break;
	    case 3: return "ternary "; break;
	    default:
		memset( pad, 0, sizeof( pad ));
		snprintf( pad, sizeof(pad)-1, "arity %d ", arity );
		return pad;
		break;
	}
    }
    return "";
}

static void tnode_check_operator_does_not_exist( TNODE *tnode,
						 DNODE *field_list,
						 DNODE *field )
{
    TNODE *field_type = field ? dnode_type( field ) : NULL;
    int arity = field_type ? dnode_list_length( tnode_args( field_type )) : 0;

    if( dnode_list_lookup_arity( field_list, dnode_name( field ), arity )) {
	if( tnode_name( tnode )) {
	    yyerrorf( "%soperator '%s' is already defined in type '%s'",
		      arity_name( arity ), dnode_name( field ),
		      tnode_name( tnode ));
	} else {
	    yyerrorf( "%soperator '%s' is already defined in the current type",
		      arity_name( arity ), dnode_name( field ));
	}
    }
}

TNODE *new_tnode_composite( char *name, TNODE *element_type, cexception_t *ex )
{
    cexception_t inner;
    TNODE * volatile node = new_tnode( ex );

    cexception_guard( inner ) {
	node->kind = TK_COMPOSITE;
	node->flags |= TF_IS_REF;
	node->name = strdupx( name, &inner );
	node->element_type = element_type;
    }
    cexception_catch {
	delete_tnode( node );
	cexception_reraise( inner, ex );
    }

    return node;
}

TNODE *new_tnode_composite_synonim( TNODE *composite_type,
				    TNODE *element_type,
				    cexception_t *ex )
{
    cexception_t inner;
    TNODE *volatile created_type = NULL;

    cexception_guard( inner ) {
	created_type = new_tnode_derived( composite_type, &inner );
	tnode_set_kind( created_type, TK_COMPOSITE );
	tnode_insert_element_type( created_type, element_type );
	share_tnode( element_type );
    }
    cexception_catch {
	delete_tnode( created_type );
	cexception_reraise( inner, ex );
    }
    return created_type;
}

TNODE *new_tnode_placeholder( char *name, cexception_t *ex )
{
    cexception_t inner;
    TNODE * volatile node = new_tnode( ex );

    cexception_guard( inner ) {
	node->kind = TK_PLACEHOLDER;
	node->name = strdupx( name, &inner );
    }
    cexception_catch {
	delete_tnode( node );
	cexception_reraise( inner, ex );
    }

    return node;
}

TNODE *new_tnode_implementation( TNODE *generic_tnode,
                                 TYPETAB *generic_types,
                                 cexception_t *ex )
{
    if( !generic_tnode ) return NULL;
    if( !generic_types ) return share_tnode( generic_tnode );

    if( generic_tnode->kind == TK_PLACEHOLDER ) {
        TNODE *concrete_type = typetab_lookup( generic_types,
                                               tnode_name( generic_tnode ));
        if( concrete_type ) {
            return share_tnode( concrete_type->base_type );
        } else {
            return share_tnode( generic_tnode );
        }
    } else if( generic_tnode->kind == TK_COMPOSITE &&
	       !generic_tnode->name ) {
	cexception_t inner;
	TNODE *volatile element_tnode =
	    new_tnode_implementation( generic_tnode->element_type,
				      generic_types, ex );
	cexception_guard( inner ) {
	    TNODE *composite_type =
		new_tnode_composite( generic_tnode->name,
				     element_tnode, &inner );
            composite_type->base_type = share_tnode( generic_tnode );
            return composite_type;
	}
	cexception_catch {
	    delete_tnode( element_tnode );
	    cexception_reraise( inner, ex );
	}
	return NULL; // control should not reach this point
    } else if( generic_tnode->kind == TK_ARRAY &&
               !generic_tnode->name ) {
	cexception_t inner;
	TNODE *volatile element_tnode =
	    new_tnode_implementation( generic_tnode->element_type,
				      generic_types, ex );
	cexception_guard( inner ) {
	    TNODE *array_type =
		new_tnode_array( element_tnode, 
                                 share_tnode( generic_tnode ),
                                 &inner );
            return array_type;
	}
	cexception_catch {
	    delete_tnode( element_tnode );
	    cexception_reraise( inner, ex );
	}
	return NULL; // control should not reach this point
    } else {
        return share_tnode( generic_tnode );
    }
}

TNODE *tnode_move_operators( TNODE *dst, TNODE *src )
{
    assert( dst );
    assert( src );

    dst->operators = dnode_append( src->operators, dst->operators );
    dst->conversions = dnode_append( src->conversions, dst->conversions );
    src->operators = NULL;
    src->conversions = NULL;

    return dst;
}

TNODE *tnode_copy_operators( TNODE *dst, TNODE *src, cexception_t *ex )
{
    DNODE *dnow = NULL;
    DNODE * volatile newop = NULL;
    TNODE * volatile newtype = NULL;
    DNODE * volatile newargs = NULL;
    DNODE * volatile newretvals = NULL;
    cexception_t inner;

    assert( dst );
    assert( src );
    assert( !dst->operators );
    assert( !dst->conversions );

    /* dst->operators = src->operators; */
    /* dst->conversions = src->conversions; */

    cexception_guard( inner ) {
        for( dnow = src->operators; dnow != NULL; dnow = dnode_next( dnow )) {
            TNODE *old_type = dnode_type( dnow );
            newop = clone_dnode( dnow, &inner );

            newargs =
                clone_dnode_list_with_replaced_types( tnode_args( old_type ),
                                                      src, dst, &inner );

            newretvals =
                clone_dnode_list_with_replaced_types( tnode_retvals( old_type ),
                                                      src, dst, &inner );

            newtype = new_tnode_operator( tnode_name(old_type), newargs, 
                                          newretvals, &inner );

            newretvals = newargs = NULL;
            dnode_replace_type( newop, newtype );
            newtype = NULL;
            tnode_insert_single_operator( dst, newop );
            newop = NULL;
        }
    }
    cexception_catch {
        delete_dnode( newop );
        delete_tnode( newtype );
        delete_dnode( newargs );
        delete_dnode( newretvals );
        cexception_reraise( inner, ex );
    }

    return dst;
}

static TNODE *tnode_finish_struct_or_class( TNODE * volatile node,
                                            type_kind_t type_kind,
                                            cexception_t *ex )
{
    node->kind = type_kind;
    node->flags |= TF_IS_REF;
    if( node->base_type && node->base_type->destructor &&
        !node->destructor ) {
        node->destructor = share_dnode( node->base_type->destructor );
    }
    return node;
}

TNODE *tnode_finish_struct( TNODE * volatile node, cexception_t *ex )
{
    return 
        tnode_finish_struct_or_class( node, TK_STRUCT, ex );
}

TNODE *tnode_finish_class( TNODE * volatile node,
			   cexception_t *ex )
{
    return 
        tnode_finish_struct_or_class( node, TK_CLASS, ex );
}

TNODE *tnode_finish_interface( TNODE * volatile node,
                               ssize_t interface_nr,
			       cexception_t *ex )
{
    DNODE *curr_method;

    node->interface_nr = interface_nr;

    foreach_dnode( curr_method, node->methods ) {
        TNODE *curr_method_type = dnode_type( curr_method );
        curr_method_type->interface_nr = node->interface_nr;
    }

    return 
        tnode_finish_struct_or_class( node, TK_INTERFACE, ex );
}

TNODE *tnode_finish_enum( TNODE * volatile node,
			  char *name,
			  TNODE *base_type,
			  cexception_t *ex )
{
    node->kind = TK_ENUM;

    assert( !node->name );
    node->name = strdupx( name, ex );

    if( base_type ) {
	if( node->size == 0 ) {
	    node->size = tnode_size( base_type );
	}
	node->base_type = share_tnode( base_type );
    } else {
	node->size = 0;
	node->base_type = NULL;
    }

#if 0
    if( base_type && base_type->operators ) {
	node->operators = share_dnode( base_type->operators );
    }
#endif

    return node;
}

TNODE *tnode_merge_field_lists( TNODE *dst, TNODE *src )
{
    assert( dst );
    assert( src );

    dst->fields = dnode_append( dst->fields, src->fields );
    src->fields = NULL;

    return dst;
}

DNODE *tnode_fields( TNODE *tnode )
{
    assert( tnode );
    return tnode->fields;
}

DNODE *tnode_lookup_field( TNODE *tnode, char *field_name )
{
    DNODE *field;

    assert( tnode );

    field = dnode_list_lookup( tnode->fields, field_name );

    if( !field ) {
        field = dnode_list_lookup( tnode->methods, field_name );
    }

    if( field ) {
	return field;
    } else if( tnode->base_type ) {
	return tnode_lookup_field( tnode->base_type, field_name );
    } else {
	return NULL;
    }
}

DNODE *tnode_lookup_method( TNODE *tnode, char *method_name )
{
    DNODE *method;

    assert( tnode );

    method = dnode_list_lookup( tnode->methods, method_name );

    if( method ) {
	return method;
    } else if( tnode->base_type ) {
	return tnode_lookup_method( tnode->base_type, method_name );
    } else {
	return NULL;
    }
}

DNODE *tnode_lookup_method_prototype( TNODE *tnode, char *method_name )
{
    DNODE *method;

    assert( tnode );

    method = dnode_list_lookup( tnode->methods, method_name );

    if( method ) {
	return method;
    } else if( tnode->base_type && tnode->kind != TK_INTERFACE ) {
	return tnode_lookup_method_prototype( tnode->base_type, method_name );
    } else {
	return NULL;
    }
}

DNODE *tnode_lookup_operator( TNODE *tnode, char *operator_name, int arity )
{
    DNODE *operator = NULL;

    operator = tnode ?
	dnode_list_lookup_arity( tnode->operators, operator_name, arity ) :
	NULL;

    if( !operator && tnode && tnode->base_type ) {
	operator =
	    tnode_lookup_operator( tnode->base_type, operator_name, arity );
    }

    return operator;
}

DNODE *tnode_lookup_operator_nonrecursive( TNODE *tnode, char *operator_name, int arity )
{
    DNODE *operator = NULL;

    operator = tnode ?
	dnode_list_lookup_arity( tnode->operators, operator_name, arity ) :
	NULL;

    return operator;
}

DNODE *tnode_lookup_conversion( TNODE *tnode, TNODE *src_type )
{
    DNODE *conversion = NULL;
    char *src_type_name = src_type ? tnode_name( src_type ) : NULL;

    if( !src_type_name )
        return NULL;

    conversion = tnode ?
	dnode_list_lookup( tnode->conversions, src_type_name ) :
	NULL;

    if( !conversion && tnode && src_type->base_type &&
	( src_type->kind == TK_DERIVED || src_type->kind == TK_ENUM )) {
	conversion = tnode_lookup_conversion( tnode, src_type->base_type );
    }

    if( !conversion && tnode && tnode->base_type &&
	tnode->kind == TK_DERIVED && tnode_has_flags( tnode, TF_IS_EQUIVALENT )) {
	conversion = tnode_lookup_conversion( tnode->base_type, src_type );
    }

    return conversion;
}

TNODE *tnode_lookup_interface( TNODE *class_tnode, char *name )
{
    TLIST *curr;

    assert( class_tnode );
    foreach_tlist( curr, class_tnode->interfaces ) {
        TNODE *base_interface;
        TNODE *curr_tnode = tlist_data( curr );
        char *curr_name = tnode_name( curr_tnode );
        if( strcmp( name, curr_name ) == 0 ) {
            return curr_tnode;
        }
        for( base_interface = curr_tnode->base_type; base_interface;
             base_interface = base_interface->next ) {
            curr_name = tnode_name( base_interface );
            if( strcmp( name, curr_name ) == 0 ) {
                return curr_tnode;
            }
        }
    }
    return NULL;
}

DNODE *tnode_lookup_argument( TNODE *tnode, char *argument_name )
{
    assert( tnode );
    return dnode_list_lookup( tnode->args, argument_name );
}

TNODE *tnode_set_name( TNODE* node, char *name, cexception_t *ex )
{
    assert( node );
    assert( !node->name );
    node->name = strdupx( name, ex );
    return node;
}

TNODE *tnode_set_suffix( TNODE* node, const char *suffix, cexception_t *ex )
{
    assert( node );
    assert( !node->suffix );
    node->suffix = strdupx( suffix, ex );
    return node;
}

TNODE *tnode_set_interface_nr( TNODE* node, ssize_t nr )
{
    assert( node );
    assert( node->interface_nr == 0 );
    node->interface_nr = nr;
    return node;
}

char *tnode_name( TNODE *tnode )
{
    assert( tnode );
    return tnode->name;
}

char *tnode_suffix( TNODE *tnode )
{
    assert( tnode );
    return tnode->suffix;
}

ssize_t tnode_size( TNODE *tnode )
{
    assert( tnode );
    return tnode->size;
}

ssize_t tnode_number_of_references( TNODE *tnode )
{
    assert( tnode );
    return tnode->nrefs;
}

ssize_t tnode_interface_number( TNODE *tnode )
{
    assert( tnode );
    return tnode->interface_nr;
}

TLIST *tnode_interface_list( TNODE *tnode )
{
    assert( tnode );
    return tnode->interfaces;
}

ssize_t tnode_max_interface( TNODE *class_descr )
{
    ssize_t max_interface = 0;
    TLIST *curr;

    assert( class_descr );

    foreach_tlist( curr, class_descr->interfaces ) {
        TNODE *curr_type = tlist_data( curr );
        ssize_t interface_nr = tnode_interface_number( curr_type );
        if( max_interface < interface_nr ) {
            max_interface = interface_nr;
        }
    }

    return max_interface;
}

ssize_t tnode_base_class_count( TNODE *tnode )
{
    ssize_t count = 0;

    if( !tnode )
        return 0;

    while( tnode->base_type && tnode->base_type->kind == TK_CLASS ) {
        count ++;
        tnode = tnode->base_type;
    }

    return count;
}

int tnode_align( TNODE *tnode )
{
    assert( tnode );
    if( tnode_is_reference( tnode )) {
        return REF_SIZE;
    } else {
        if( tnode->align != 0 )
            return tnode->align;
        else
            return tnode->size;
    }
}

type_kind_t tnode_kind( TNODE *tnode ) { assert( tnode ); return tnode->kind; }

DNODE *tnode_args( TNODE* tnode )
{
    assert( tnode );
    return tnode->args;
}

#if 1
DNODE *tnode_arg_next( TNODE* tnode, DNODE *arg )
{
    assert( tnode );
    if( !arg ) { return tnode->args; }
    else       { return dnode_next(arg); }
}
#endif

#if 0
DNODE *tnode_arg_prev( TNODE* tnode, DNODE *arg )
{
    assert( tnode );
    if( !arg ) { return dnode_list_last( tnode->args ); }
    else       { return dnode_prev(arg); }
}
#endif

DNODE *tnode_retvals( TNODE* tnode )
{
    assert( tnode );
    return tnode->return_vals;
}

DNODE *tnode_retval_next( TNODE* tnode, DNODE *retval )
{
    assert( tnode );
    if( !retval ) { return tnode->return_vals; }
    else          { return dnode_next(retval); }
}

TNODE *tnode_set_size( TNODE *tnode, int size )
{
    assert( tnode );
    assert( tnode->size == 0 );
    tnode->size = size;
    return tnode;
}

const char *tnode_kind_name( TNODE *tnode )
{
    static char buffer[80];

    if( !tnode )
        return "(null)";

    switch( tnode->kind ) {
        case TK_NONE:          return "<no kind>";
        case TK_BOOL:          return "bool";
        case TK_INTEGER:       return "integer";
        case TK_REAL:          return "real";
        case TK_STRING:        return "string";
        case TK_PRIMITIVE:     return "primitive";
        case TK_ADDRESSOF:     return "addressof";
        case TK_ARRAY:         return "array";
        case TK_ENUM:          return "enum";
        case TK_STRUCT:        return "struct";
        case TK_CLASS:         return "class";
        case TK_BLOB:          return "blob";
        case TK_FUNCTION:      return "function";

        case TK_PLACEHOLDER:   return "placeholder";
        case TK_DERIVED:       return "derived";
        case TK_REF:           return "ref";
        case TK_FUNCTION_REF:  return "functionref";
        case TK_NULLREF:       return "nullref";
        case TK_TYPE:          return "type";
        default:
            snprintf( buffer, sizeof(buffer)-1, "type kind %d", tnode->kind );
            buffer[sizeof(buffer)-1] = '\0';
            return buffer;
    }
    assert( 0 ); /* should never reach this point */
    return( 0 ); /* suppress 'control reaches end of non-void function' */
}

#include <stdio.h>

void tnode_print( TNODE *tnode )
{
    tnode_print_indent( tnode, 0 );
}

void tnode_print_indent( TNODE *tnode, int indent )
{
    assert( tnode );
    printf( "%*sTNODE ", indent, "" );
    printf( "%s ", tnode_kind_name( tnode ));
    printf( "size = %d ", tnode->size );
    printf( "%s ", tnode->name ? tnode->name : "-" );
    putchar( '\n' );
    if( tnode->element_type )
        tnode_print_indent( tnode->element_type, indent+3 );
}

static TNODE *tnode_insert_single_enum_value( TNODE* tnode, DNODE *field )
{
    assert( tnode );
    tnode_check_field_does_not_exist( tnode, tnode->fields, "enumerator value",
				      field );
    tnode->fields = dnode_append( field, tnode->fields );
    return tnode;
}

#define ALIGN_NUMBER(N,lim)  ( (N) += ((lim) - ((int)(N)) % (lim)) % (lim) )

TNODE *tnode_insert_fields( TNODE* tnode, DNODE *field )
{
    TNODE *field_type;
    type_kind_t field_kind;
    size_t field_size, field_align;
    DNODE *current;

    assert( tnode );
    tnode_check_field_does_not_exist( tnode, tnode->fields, "field", field );

    foreach_dnode( current, field ) {
	field_type = dnode_type( current );
	field_kind = field_type ? tnode_kind( field_type ) : TK_NONE;
        field_size = tnode_is_reference( field_type ) ?
            REF_SIZE : 
            ( field_type ? tnode_size( field_type ) : 0 );
        field_align = field_type ? tnode_align( field_type ) : 0;

        DNODE *last_field =
            tnode->fields ? dnode_list_last( tnode->fields ) : NULL;
        TNODE *last_type = last_field ? dnode_type( last_field ) : NULL;
        if( last_type && tnode_kind( last_type ) == TK_PLACEHOLDER ) {
            yyerrorf( "A generic field ('%s') must be a single last "
                      "field in a structure", dnode_name( last_field ));
        }

	if( field_kind != TK_FUNCTION ) {
            if( tnode_is_reference( field_type ) ||
                field_kind == TK_PLACEHOLDER ) {
                dnode_set_offset( current, tnode->nextrefoffs -
                                  sizeof(alloccell_t) - REF_SIZE );
                tnode->nextrefoffs -= REF_SIZE;
                tnode->nrefs -= 1;
                tnode->size += REF_SIZE;
            } else {
                if( field_size != 0 ) {
                    ssize_t old_offset = tnode->nextnumoffs;
                    ALIGN_NUMBER( tnode->nextnumoffs, field_align );
                    dnode_set_offset( current, tnode->nextnumoffs );
                    tnode->nextnumoffs += field_size;
                    tnode->size += tnode->nextnumoffs - old_offset;
                    if( tnode->align < field_align )
                        tnode->align = field_align;
                }
            }
	}
        if( field_kind == TK_PLACEHOLDER ) {
            /* For generic type value placeholders, we must allocte
               also memory at a positive structure field offset to
               hold numeric value of the future type, in addition to
               the reference value for which the memory at the
               negative offset has just been allocated before: */
            ssize_t bytes = sizeof(ssize_t);
            ssize_t bits = (CHAR_BIT * bytes)/2;
            ssize_t max_size = ((ssize_t)1) << bits;
            ssize_t old_offset = tnode->nextnumoffs;
            field_size = sizeof(union stackunion);
#if 1
            field_align = sizeof(int);
            ALIGN_NUMBER( tnode->nextnumoffs, field_align );
#endif
            /* printf( ">>> bits = %d, max_size = %d\n", bits, max_size ); */
            if( dnode_offset( current ) >= max_size ||
                tnode->nextnumoffs >= max_size ) {
                yyerrorf( "placeholder field '%s' has offset %d "
                          "which is larger than the size %d which we can "
                          "handle in this implementation",
                          dnode_name( current ), max_size );
            }
#if 0
            ssize_t combined_offset = (dnode_offset( current ) << bits) |
                tnode->nextnumoffs;
            printf( ">>> pos offset = %d, neg offset = %d, combined offset = %d\n",
                    tnode->nextnumoffs, dnode_offset( current ), combined_offset );
#endif
            dnode_update_offset( current, 
                                 (dnode_offset( current ) << bits) |
                                 tnode->nextnumoffs );
            tnode->nextnumoffs += field_size;
            tnode->size += tnode->nextnumoffs - old_offset;
            tnode_set_flags( tnode, TF_HAS_PLACEHOLDER );
        }
        if( field_size == 0 && field_type && field_kind != TK_FUNCTION &&
            field_kind != TK_PLACEHOLDER ) {
            yyerrorf( "field '%s' has zero size", dnode_name( current ));
	}
    }

    // printf( ">>> field '%s' offset = %d\n", dnode_name( field ), dnode_offset( field ));

    tnode->fields = dnode_append( tnode->fields, field );

    return tnode;
}

TNODE *tnode_insert_constructor( TNODE* tnode, DNODE *constructor )
{
    char msg[100];

    assert( tnode );
    assert( constructor );

    char *constructor_name = dnode_name( constructor );
    DNODE *current_constructor =
        tnode_lookup_constructor( tnode, constructor_name );

    if( current_constructor == constructor ) {
        return tnode;
    }

    if( !current_constructor ) {
        if( constructor_name && *constructor_name != '\0' ) {
            /* constructor_name is not "": */
            tnode->constructor =
                dnode_append( tnode->constructor, constructor );
        } else {
            tnode->constructor =
                dnode_append( constructor, tnode->constructor );
        }
    } else {
        if( !dnode_function_prototypes_match_msg( tnode->constructor, constructor,
                                                  msg, sizeof(msg))) {
            yyerrorf( "Prototype of constructor %s() does not match "
                      "inherited definition -- %s", dnode_name( constructor ),
                      msg );
            delete_dnode( constructor );
        } else {
            delete_dnode( tnode->constructor );
            tnode->constructor = constructor;
        }
    }
    return tnode;
}

TNODE *tnode_insert_destructor( TNODE* tnode, DNODE *destructor )
{
    assert( tnode );
    assert( destructor );

    if( !tnode->destructor || tnode->destructor == destructor ) {
        tnode->destructor = destructor;
    } else {
        yyerrorf( "destructor is already declared for class '%s'", 
                  tnode_name( tnode ));
    }
    return tnode;
}

TNODE *tnode_insert_single_method( TNODE* tnode, DNODE *method )
{
    DNODE *existing_method;
    DNODE *inherited_method;
    ssize_t method_offset;
    char *method_name = method ? dnode_name( method ) : NULL;
    char msg[100];

    assert( tnode );

    existing_method =
        tnode_check_method_does_not_exist( tnode, tnode->methods, method );

    if( !existing_method ) {
        TNODE *method_type = method ? dnode_type( method ) : NULL;
        ssize_t method_interface_nr = method_type ?
            tnode_interface_number( method_type ) : 0;

	inherited_method = tnode->base_type ? 
	    tnode_lookup_method( tnode->base_type, method_name ) : NULL;

	if( inherited_method ) {
            if( tnode->kind == TK_INTERFACE ) {
		yyerrorf( "interface '%s' should not override "
                          "method '%s' inherited from '%s'",
                          tnode->name, dnode_name( method ),
                          tnode->base_type->name );
            } else
            if( !dnode_function_prototypes_match_msg( inherited_method, method,
                                                      msg, sizeof(msg))) {
		yyerrorf( "Prototype of method %s() does not match "
			  "inherited definition:\n%s", dnode_name( method ),
			  msg );
	    }
	    method_offset = dnode_offset( inherited_method );
	} else {
            if( method_interface_nr == 0 ) {
                if( tnode->max_vmt_offset == 0 &&
                    tnode->kind != TK_INTERFACE ) {
                    /* Reserve the 0-th offset of the VMT for the
                       destructor: */
#if 0
                    printf( ">>> reserving offset 0 for destructor\n" );
#endif
                    tnode->max_vmt_offset++;
                }
                tnode->max_vmt_offset++;
#if 0
                printf( ">>> advancing VMT offset to %d for type '%s'\n",
                        tnode->max_vmt_offset, tnode_name( tnode ));
#endif
                method_offset = tnode->max_vmt_offset;
            }
	}

        tnode_set_flags( tnode, TF_IS_REF );
	tnode->methods = dnode_append( method, tnode->methods );
        if( method_interface_nr == 0 ) {
#if 0
            printf( ">>> setting offset %d for method '%s', interface no. %d\n",
                    method_offset, dnode_name( method ), method_interface_nr );
#endif
            dnode_set_offset( method, method_offset );
        }
    } else {
 	if( !dnode_function_prototypes_match_msg( existing_method, method,
						  msg, sizeof(msg))) {
	    yyerrorf( "Prototype of method %s() does not match "
		      "previous definition:\n%s", dnode_name( method ),
		      msg );
	}
	delete_dnode( method );
    }

    return tnode;
}

TNODE *tnode_insert_single_operator( TNODE* tnode, DNODE *operator )
{
    assert( tnode );
    tnode_check_operator_does_not_exist( tnode, tnode->operators, operator );
    tnode->operators = dnode_append( tnode->operators, operator );
    return tnode;
}

TNODE *tnode_insert_single_conversion( TNODE* tnode, DNODE *conversion )
{
    assert( tnode );
    tnode_check_field_does_not_exist( tnode, tnode->conversions,
				      "type conversion", conversion );
    tnode->conversions = dnode_append( conversion, tnode->conversions );
    return tnode;
}

TNODE *tnode_insert_type_member( TNODE *tnode, DNODE *member )
{
    TNODE *member_type = member ? dnode_type( member ) : NULL;

    assert( tnode );

    if( member ) {
	if( tnode_is_conversion( member_type )) {
	    tnode_insert_single_conversion( tnode, member );
	} else
	if( tnode_is_operator( member_type )) {
	    tnode_insert_single_operator( tnode, member );
        } else
	if( tnode_is_method( member_type )) {
	    tnode_insert_single_method( tnode, member );
        } else
	if( tnode_is_constructor( member_type )) {
	    tnode_insert_constructor( tnode, member );
        } else
	if( tnode_is_destructor( member_type )) {
	    tnode_insert_destructor( tnode, member );
	} else {
	    tnode_insert_fields( tnode, member );
	}
    }
    return tnode;
}

TNODE *tnode_insert_enum_value_list( TNODE *tnode, DNODE *list )
{
    DNODE *member, *next;

    member = list;
    while( member ) {
	next = dnode_next( member );
	dnode_disconnect( member );
	tnode_insert_enum_value( tnode, member );
	member = next;
    }
    return tnode;
}

TNODE *tnode_insert_enum_value( TNODE *tnode, DNODE *member )
{
    ssize_t enum_value = 0, last_enum_value = -1;
    char *member_name;

    assert( tnode );

    if( !member ) return tnode;

    member_name = dnode_name( member );
    if( member_name && strcmp( member_name, "..." ) == 0 ) {
	tnode_set_flags( tnode, TF_EXTENDABLE_ENUM );
	delete_dnode( member );
	return tnode;
    }

    if( tnode->fields ) {
	DNODE *field;
	ssize_t current_enum_value;

	last_enum_value = dnode_ssize_value( tnode->fields );

	foreach_dnode( field, dnode_next( tnode->fields )) {
	    current_enum_value = dnode_ssize_value( field );
	    if( last_enum_value < current_enum_value ) {
		last_enum_value = current_enum_value;
	    }
	}
    }
    enum_value = dnode_ssize_value( member );
    if( enum_value == 0 ) {
	enum_value = last_enum_value + 1;
	dnode_set_ssize_value( member, enum_value );
    }
    tnode_insert_single_enum_value( tnode, member );

    return tnode;
}

ssize_t tnode_max_vmt_offset( TNODE *tnode )
{
    assert( tnode );
    return tnode->max_vmt_offset;
}

ssize_t tnode_vmt_offset( TNODE *tnode )
{
    assert( tnode );
    return tnode->vmt_offset;
}

ssize_t tnode_set_vmt_offset( TNODE *tnode, ssize_t offset )
{
    assert( tnode );
    return tnode->vmt_offset = offset;
}

DNODE *tnode_methods( TNODE *tnode )
{
    assert( tnode );
    return tnode->methods;
}

TNODE *tnode_base_type( TNODE *tnode )
    { assert( tnode ); return tnode->base_type; }

TNODE *tnode_insert_base_type( TNODE *tnode, TNODE *base_type )
{
    DNODE *field;
    assert( tnode );
    assert( !tnode->base_type );
    assert( base_type != tnode );

    if( base_type ) {
        tnode->base_type = base_type;
        if( tnode->kind != TK_INTERFACE )
            tnode->max_vmt_offset = base_type->max_vmt_offset;
	tnode->size += tnode_size( base_type );
	tnode->nrefs += base_type->nrefs;
	tnode->nextnumoffs += base_type->nextnumoffs;
	tnode->nextrefoffs += base_type->nextrefoffs;
        if( tnode->align < base_type->align ) {
            tnode->align = base_type->align;
        }
	foreach_dnode( field, tnode->fields ) {
	    TNODE *field_type = dnode_type( field );
	    type_kind_t field_kind =
		field_type ? tnode_kind( field_type ) : TK_NONE;
	    if( field_kind != TK_FUNCTION ) {
                if( tnode_is_reference( field_type )) {
                    dnode_set_offset( field,
                                      dnode_offset( field ) +
                                      base_type->nextrefoffs );
                } else {
                    dnode_set_offset( field,
                                      dnode_offset( field ) +
                                      base_type->nextnumoffs );
                }
	    }
	}
    }

    return tnode;
}

TNODE *tnode_insert_interfaces( TNODE *tnode, TLIST *interfaces )
{
    assert( tnode );
    assert( !tnode->interfaces );
    tnode->interfaces = interfaces;
    return tnode;
}

TNODE *tnode_first_interface( TNODE *class_tnode )
{
    assert( class_tnode );

    if( !class_tnode->interfaces ) {
        return NULL;
    } else {
        return tlist_data( class_tnode->interfaces );
    }
}

TNODE *tnode_element_type( TNODE *tnode )
    { assert( tnode ); return tnode->element_type; }

TNODE *tnode_insert_element_type( TNODE* tnode, TNODE *element_type )
{
    assert( tnode );

    if( !element_type )
	return tnode;

    assert( !tnode->element_type || 
	    (tnode->kind == TK_COMPOSITE &&
	     tnode->element_type->kind == TK_PLACEHOLDER));

    if( tnode->element_type ) {
	delete_tnode( tnode->element_type );
    }

    tnode->element_type = element_type;

    return tnode;
}

TNODE *tnode_append_element_type( TNODE* tnode, TNODE *element_type )
{
    if( !tnode ) {
        return element_type;
    }
    if( !tnode->element_type ) {
	tnode_insert_element_type( tnode, element_type );
    } else {
	tnode_append_element_type( tnode->element_type, element_type );
    }
    return tnode;
}

#if 0
TNODE *tnode_insert_function_parameters( TNODE* tnode, DNODE *parameters )
{
    assert( tnode );
    assert( !tnode->args );
    tnode->args = parameters;
    return tnode;
}
#endif

TNODE *tnode_set_flags( TNODE* node, type_flag_t flags )
{
    assert( node );
    node->flags |= flags;
    return node;
}

TNODE *tnode_reset_flags( TNODE* node, type_flag_t flags )
{
    assert( node );
    node->flags &= ~flags;
    return node;
}

int tnode_has_flags( TNODE *tnode, type_flag_t flags )
{
    assert( tnode );
    return (tnode->flags & flags);
}

TNODE *tnode_set_has_references( TNODE *tnode )
{
    assert( tnode );
    return tnode_set_flags( tnode, TF_HAS_REFS );    
}

TNODE *tnode_set_has_no_numbers( TNODE *tnode )
{
    assert( tnode );
    return tnode_set_flags( tnode, TF_HAS_NO_NUMBERS );
}

int tnode_has_references( TNODE *tnode )
{
    assert( tnode );
    return ( tnode->flags & TF_HAS_REFS ) != 0;
}

int tnode_has_numbers( TNODE *tnode )
{
    assert( tnode );
    return ( tnode->flags & TF_HAS_NO_NUMBERS ) == 0;
}

int tnode_is_addressof( TNODE *tnode )
{
    assert( tnode );
    return (tnode->kind == TK_ADDRESSOF);
}

int tnode_is_reference( TNODE *tnode )
{
    if( tnode )
	return ( tnode->flags & TF_IS_REF ) != 0;
    else
	return 0;
}

int tnode_is_non_null_reference( TNODE *tnode )
{
    if( tnode && tnode_is_reference( tnode ))
	return ( tnode->flags & TF_NON_NULL ) != 0;
    else
	return 0;
}

int tnode_has_non_null_ref_field( TNODE *tnode )
{
    DNODE *field;

    if( !tnode ) return 0;

    foreach_dnode( field, tnode->fields ) {
        TNODE *field_type = dnode_type( field );
        if( tnode_is_non_null_reference( field_type )) {
            return 1;
        }
    }

    return 0;
}

int tnode_is_integer( TNODE *tnode )
{
    if( tnode )
	return ( tnode->kind == TK_INTEGER ) != 0;
    else
	return 0;
}

TNODE *tnode_set_kind( TNODE *tnode, type_kind_t kind )
{
    assert( tnode );
    tnode->kind = kind;
    return tnode;
}

static type_kind_t tnode_kind_from_string( const char *kind_name )
{
    if( strcmp( kind_name, "integer" ) == 0 )
	return TK_INTEGER;
    if( strcmp( kind_name, "real" ) == 0 )
	return TK_REAL;
    if( strcmp( kind_name, "bool" ) == 0 )
	return TK_BOOL;
    if( strcmp( kind_name, "string" ) == 0 )
	return TK_STRING;
    if( strcmp( kind_name, "ref" ) == 0 )
	return TK_REF;
    return TK_NONE;
}

TNODE *tnode_set_kind_from_string( TNODE *tnode, const char *kind_name,
				   cexception_t *ex )
{
    type_kind_t tkind = tnode_kind_from_string( kind_name );

    if( tkind != TK_NONE ) {
	return tnode_set_kind( tnode, tkind );
    } else {
	yyerrorf( "type kind '%s' is unknown", kind_name );
	return NULL;
    }
}

TNODE *tnode_set_attribute( TNODE *tnode, ANODE *attribute, cexception_t *ex )
{
    anode_kind_t akind = attribute ? anode_kind( attribute ) : AK_NONE;

    assert( tnode );
    assert( attribute );

    if( akind == AK_INTEGER_ATTRIBUTE ) {
	return tnode_set_integer_attribute( tnode, anode_name( attribute ),
					    anode_integer_value( attribute ), ex );
    } else
    if( akind == AK_STRING_ATTRIBUTE ) {
	return tnode_set_string_attribute( tnode, anode_name( attribute ),
					   anode_string_value( attribute ), ex );
    } else {
	yyerrorf( "type attributes of kind '%s' are curently unknown to "
		  "the compiler", attribute_kind_name( akind ));
	return NULL;
    }
    return tnode;
}

TNODE *tnode_set_integer_attribute( TNODE *tnode, const char *attr_name,
				    ssize_t attr_value, cexception_t *ex )
{
    assert( tnode );
    if( strcmp( attr_name, "size" ) == 0 ) {
        tnode->size = attr_value;
	return tnode;
    }
    if( strcmp( attr_name, "reference" ) == 0 ) {
	tnode->flags |= TF_IS_REF;
	return tnode;
    }
    if( strcmp( attr_name, "immutable" ) == 0 ) {
	tnode->flags |= TF_IS_IMMUTABLE;
	return tnode;
    }
    yyerrorf( "Unknown type attribute '%s'", attr_name );
    return NULL;
}

TNODE *tnode_set_string_attribute( TNODE *tnode, const char *attr_name,
				   const char *attr_value, cexception_t *ex )
{
    assert( tnode );
    if( strcmp( attr_name, "suffix" ) == 0 ) {
	return tnode_set_suffix( tnode, attr_value, ex );
    }
    if( strcmp( attr_name, "kind" ) == 0 ) {
	return tnode_set_kind_from_string( tnode, attr_value, ex );
    }
    yyerrorf( "Unknown type attribute '%s'", attr_name );
    return NULL;
}

DNODE *tnode_default_constructor( TNODE *tnode )
{
    assert( tnode );
    return tnode->constructor;
}

DNODE *tnode_lookup_constructor( TNODE *tnode, const char *name )
{
    DNODE *curr;

    if( !name ) return NULL;

    assert( tnode );
    for( curr = tnode->constructor; curr != NULL; curr = dnode_next( curr )) {
        char *curr_name = dnode_name( curr );
        if( curr_name && strcmp( curr_name, name ) == 0 ) {
            return curr;
        }
    }

    return NULL;
}

DNODE *tnode_destructor( TNODE *tnode )
{
    assert( tnode );
    return tnode->destructor;
}

TNODE *tnode_next( TNODE* list )
{
    if( !list ) return NULL;
    else return list->next;
}

TNODE *tnode_drop_last_argument( TNODE *tnode )
{
    if( tnode ) {
        if( tnode->args ) {
            if( !dnode_next( tnode->args )) {
                delete_dnode( tnode->args );
                tnode->args = NULL;
            } else {
                tnode->args = dnode_remove_last( tnode->args );
            }
        }
    }

    return tnode;
}
