/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* tnode -- representation of the type definition parse tree */
/* tnode tree is built by the parser (hlc.y) */
/* from this tnode tree a type symbol table is built */

/* exports: */
#include <tnode.h>

/* uses: */
#include <string.h> /* for memset() */
#include <alloccell.h>
#include <tcodes.h>
#include <allocx.h>
#include <stringx.h>
#include <assert.h>
#include <yy.h>

struct TNODE {
    type_kind_t kind;     /* what kind of type is it: simple type,
			     struct, class, vector, function type, etc. */
    char *name;           /* name of the type ( 'int', 'real', etc. ) */
    char *suffix;         /* suffix that distinguishes constants of this type */
    TNODE *base_type;     /* base type of the current type, if any;
			     for functions this is a type of the
			     returned value */
    TNODE *element_type;  /* for arrays, contains trype of the array
			     element; for 'addressof' type, contains
			     description of the addressed element. */
    type_flag_t flags;    /* flags for different modifiers */
    ssize_t size;         /* size of variable of a given type, in bytes */
    ssize_t nrefs;        /* number of fields in the type (structure, class,
			     etc.) that are references and should be garbage
			     collected */
    ssize_t max_vmt_offset;
                          /* maximum Virtual method offset assigned in
			     this type.*/
    ssize_t vmt_offset;   /* offset of the VMT in the static data area. */

    ssize_t attr_size;    /* attr_size is the size of the type set via
			     'type attributes', i.e. specified as
			     'size = 1234' statements in the type
			     definition; this size should be added to
			     the size of explicitely declared
			     fields. */

    long rcount;          /* reference count */

    DNODE *fields;        /* for structure types, contains a list of
			     definitions of the fields; for enum
			     types, contains a list of enumerated
			     values. */

    DNODE *operators;     /* Operators declared for this type */

    DNODE *conversions;   /* Operators to convert values into the
			     current type */

    DNODE *methods;       /* (Virtual) methods of the current class
                             or struct */

    DNODE *args;          /* declarations of the function's formal
			     arguments, NULL if function has no arguments */
    DNODE *return_vals;   /* value (or several values), returned by the
			     function */
    TNODE *next;
};

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

    assert( name );
    cexception_guard( inner ) {
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

    assert( name );
    cexception_guard( inner ) {
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

TNODE *new_tnode_synonim( TNODE *base, cexception_t *ex )
{
    cexception_t inner;
    TNODE *node = new_tnode( ex );

    cexception_guard( inner ) {
	/* node->kind = base->kind; */
	node->kind = TK_DERIVED;
	/* base->name is not copied */
	while( base && base->kind == TK_DERIVED )
	    base = base->base_type;
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
	created_type = new_tnode_synonim( composite_type, &inner );
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
    } else {
        return share_tnode( generic_tnode );
    }
}

TNODE *tnode_move_operators( TNODE *dst, TNODE *src )
{
    assert( dst );
    assert( src );
    assert( !dst->operators );
    assert( !dst->conversions );

    dst->operators = src->operators;
    dst->conversions = src->conversions;
    src->operators = NULL;
    src->conversions = NULL;

    return dst;
}

static TNODE *tnode_finish_struct_or_class( TNODE * volatile node,
                                            type_kind_t type_kind,
                                            cexception_t *ex )
{
    node->kind = type_kind;
    node->flags |= TF_IS_REF;
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

DNODE *tnode_lookup_conversion( TNODE *tnode, char *src_type_name )
{
    DNODE *conversion = NULL;

    conversion = tnode ?
	dnode_list_lookup( tnode->conversions, src_type_name ) :
	NULL;

#if 0
    if( !conversion && tnode && tnode->base_type &&
	( tnode->kind == TK_DERIVED || tnode->kind == TK_ENUM )) {
	conversion = tnode_lookup_conversion( tnode->base_type, src_type_name );
    }
#endif

    return conversion;
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
    return tnode->size + tnode->attr_size;
}

ssize_t tnode_number_of_references( TNODE *tnode )
{
    assert( tnode );
    return tnode->nrefs;
}

type_kind_t tnode_kind( TNODE *tnode ) { assert( tnode ); return tnode->kind; }

DNODE *tnode_args( TNODE* tnode )
{
    assert( tnode );
    return tnode->args;
}

#if 0
DNODE *tnode_arg_next( TNODE* tnode, DNODE *arg )
{
    assert( tnode );
    if( !arg ) { return tnode->args; }
    else       { return dnode_next(arg); }
}
#endif

DNODE *tnode_arg_prev( TNODE* tnode, DNODE *arg )
{
    assert( tnode );
    if( !arg ) { return dnode_list_last( tnode->args ); }
    else       { return dnode_prev(arg); }
}

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

static int tnode_retval_nr( TNODE *tnode )
{
    if( tnode->return_vals == NULL ) return 0;
    else return dnode_list_length( tnode->return_vals );
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

    switch( tnode->kind ) {
        case TK_NONE:          return "<no kind>";
        case TK_PRIMITIVE:     return "primitive";
        case TK_ARRAY:         return "array";
        case TK_FUNCTION:      return "function";
        case TK_DERIVED:       return "derived";
        case TK_PLACEHOLDER:   return "placeholder";
        case TK_REF:           return "ref";
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

static int tnode_structures_are_compatible( TNODE *t1, TNODE *t2,
					    TYPETAB *generic_types,
					    cexception_t *ex )
{
    DNODE *f1, *f2;
    TNODE *tf1, *tf2;

    f1 = t1->fields;
    f2 = t2->fields;
    while( f1 && f2 ) {
	tf1 = dnode_type( f1 );
	tf2 = dnode_type( f2 );
	if( !tnode_types_are_compatible( tf1, tf2, generic_types, ex )) {
	    return 0;
	}
	f1 = dnode_next( f1 );
	f2 = dnode_next( f2 );
    }
    if( !f1 && !f2 ) {
	return 1;
    } else {
	return 0;
    }
}

static int tnode_classes_are_compatible( TNODE *t1, TNODE *t2,
					 TYPETAB *generic_types,
					 cexception_t *ex )
{
    if( !t1 && !t2 ) return 1;
    if( !t1 || !t2 ) return 0;
    return
        tnode_structures_are_compatible( t1, t2, generic_types, ex ) &&
        tnode_classes_are_compatible( t1->base_type, t2->base_type,
				      generic_types, ex );
}

static int tnode_structures_are_identical( TNODE *t1, TNODE *t2,
					   TYPETAB *generic_types,
					   cexception_t *ex )
{
    DNODE *f1, *f2;
    TNODE *tf1, *tf2;

    f1 = t1->fields;
    f2 = t2->fields;
    while( f1 && f2 ) {
	tf1 = dnode_type( f1 );
	tf2 = dnode_type( f2 );
	if( !tnode_types_are_identical( tf1, tf2, generic_types, ex )) {
	    return 0;
	}
	f1 = dnode_next( f1 );
	f2 = dnode_next( f2 );
    }
    if( !f1 && !f2 ) {
	return 1;
    } else {
	return 0;
    }
}

static int
tnode_create_and_check_placeholder_implementation( TNODE *t1, TNODE *t2,
                                                   TYPETAB *generic_types,
                                                   int (*tnode_check_types)
                                                       ( TNODE *t1, TNODE *t2,
                                                         TYPETAB *generic_types,
                                                         cexception_t *ex ),
                                                   cexception_t *ex)
{
    TNODE *volatile placeholder_implementation =
        typetab_lookup( generic_types, t2->name );

    if( placeholder_implementation ) {
        return tnode_check_types
            ( t1, placeholder_implementation->base_type,
              generic_types, ex );
    } else {
        cexception_t inner;
        cexception_guard( inner ) {
            placeholder_implementation =
                new_tnode_placeholder( t2->name, ex );
            tnode_insert_base_type( placeholder_implementation,
                                    share_tnode( t1 ));
            typetab_insert( generic_types, t2->name,
                            placeholder_implementation, &inner );
        }
        cexception_catch {
            delete_tnode( placeholder_implementation );
            cexception_reraise( inner, ex );
        }
        return 1;
    }
}

static int
tnode_create_and_check_generic_types( TNODE *t1, TNODE *t2,
                                      TYPETAB *generic_types,
                                      int (*tnode_check_types)
                                          ( TNODE *t1, TNODE *t2,
                                            TYPETAB *generic_types,
                                            cexception_t *ex ),
                                      cexception_t *ex )
{
    if( generic_types && ( t1->kind == TK_PLACEHOLDER ||
			   t2->kind == TK_PLACEHOLDER )) {
        if( t2->kind == TK_PLACEHOLDER ) {
            if( t2->base_type ) {
                /* placeholder is already implemented: */
                return tnode_check_types
                    ( t1, t2->base_type, generic_types, ex );
            } else {
                return tnode_create_and_check_placeholder_implementation
                    ( t1, t2, generic_types, tnode_check_types, ex );
            }
        } else {
            return tnode_create_and_check_placeholder_implementation
                ( t2, t1, generic_types, tnode_check_types, ex );
        }
    }

    return 0;
}

int tnode_types_are_identical( TNODE *t1, TNODE *t2,
			       TYPETAB *generic_types,
			       cexception_t *ex )
{
    if( !t1 || !t2 ) return 0;
    if( t1 == t2 ) return 1;
    if( t1->kind == TK_IGNORE || t2->kind == TK_IGNORE ) {
	return 1;
    }
    if( t1->kind == TK_REF ) {
	return tnode_is_reference( t2 );
    }
    if( t2->kind == TK_REF ) {
	return tnode_is_reference( t1 );
    }
    if( t2->kind == TK_REF ) {
	return tnode_is_reference( t1 );
    }
    if( t1->kind == TK_BLOB && t2->kind == TK_BLOB ) {
	return 1;
    }
    if( t1->kind == TK_NULLREF ) {
	return tnode_is_reference( t2 );
    }
    if( t2->kind == TK_NULLREF ) {
	return tnode_is_reference( t1 );
    }
    if( t1->kind == TK_CLASS && t2->kind == TK_CLASS ) {
	return tnode_types_are_identical( t1, t2->base_type,
					  generic_types, ex );
    }
    if( t1->kind == TK_OPERATOR && t2->kind == TK_OPERATOR ) {
        return
	    dnode_lists_are_type_identical( t1->args, t2->args,
					    generic_types, ex ) &&
	    dnode_lists_are_type_identical( t1->return_vals,
					    t2->return_vals,
					    generic_types, ex );
    }

    if( generic_types && ( t1->kind == TK_PLACEHOLDER ||
			   t2->kind == TK_PLACEHOLDER )) {
        return tnode_create_and_check_generic_types
            ( t1, t2, generic_types, tnode_types_are_identical, ex );
    }

    if( t1->kind == TK_COMPOSITE && t2->kind == TK_COMPOSITE ) {
	if( (t1->element_type && t1->element_type->kind == TK_PLACEHOLDER) &&
	    (t2->element_type && t2->element_type->kind == TK_PLACEHOLDER) ) {
	    return (!t1->name || !t2->name ||
		    strcmp( t1->name, t2->name ) == 0);
	} else {
	    return (!t1->name || !t2->name ||
		    strcmp( t1->name, t2->name ) == 0) &&
		tnode_types_are_identical( t1->element_type, t2->element_type,
					   generic_types, ex );
	}
    }
    if( t1->name && t2->name ) return 0;
    if( (t1->kind == TK_ARRAY && t2->kind == TK_ARRAY) ||
	(t1->kind == TK_ADDRESSOF && t2->kind == TK_ADDRESSOF) ) {
	if( t1->element_type == NULL || t2->element_type == NULL ) {
	    return 1;
	} else {
	    return 
		tnode_types_are_identical( t1->element_type, t2->element_type,
					   generic_types, ex );
	}
    }
    if( t1->kind == TK_STRUCT && t2->kind == TK_STRUCT ) {
	return tnode_structures_are_identical( t1, t2,
					       generic_types, ex );
    }
    return 0;
}

int tnode_types_are_compatible( TNODE *t1, TNODE *t2,
				TYPETAB *generic_types,
				cexception_t *ex )
{
    if( !t1 || !t2 ) return 0;

    if( t1->kind == TK_DERIVED && t2->kind != TK_DERIVED ) {
	return tnode_types_are_compatible( t1->base_type, t2,
					   generic_types, ex );
    }
    if( t2->kind == TK_DERIVED && t1->kind != TK_DERIVED ) {
	return tnode_types_are_compatible( t1, t2->base_type,
					   generic_types, ex );
    }

    if( t1->kind == TK_ENUM && t2->kind != TK_ENUM ) {
	return tnode_types_are_identical( t1->base_type, t2,
					  generic_types, ex );
    }
    if( t2->kind == TK_ENUM && t1->kind != TK_ENUM ) {
	return tnode_types_are_identical( t1, t2->base_type,
					  generic_types, ex );
    }

    return tnode_types_are_identical( t1, t2, generic_types, ex );
}

static int tnode_generic_function_prototypes_match( TNODE *f1, TNODE *f2,
                                                    TYPETAB *generic_types,
                                                    char *msg, int msglen,
                                                    cexception_t *ex );

int tnode_types_are_assignment_compatible( TNODE *t1, TNODE *t2,
                                           TYPETAB *generic_types,
                                           cexception_t *ex )
{
    if( !t1 || !t2 ) return 0;
    if( t1 == t2 ) return 1;

    if( tnode_is_non_null_reference( t1 ) &&
        !tnode_is_non_null_reference( t2 )) {
        return 0;
    }

    if( t1->kind == TK_REF ) {
	return tnode_is_reference( t2 );
    }
    if( t2->kind == TK_REF ) {
	return t1->kind == TK_REF;
    }
    if( t1->kind == TK_BLOB && t2->kind == TK_BLOB ) {
	return 1;
    }
    if( t2->kind == TK_NULLREF ) {
	return tnode_is_reference( t1 );
    }

    if( t1->kind == TK_CLASS && t2->kind == TK_CLASS ) {
        return (!t1->name && tnode_classes_are_compatible( t1, t2,
							   generic_types,
							   ex )) ||
            tnode_types_are_assignment_compatible( t1, t2->base_type,
                                                   generic_types, ex );
    }

    if( generic_types && ( t1->kind == TK_PLACEHOLDER ||
			   t2->kind == TK_PLACEHOLDER )) {
        return tnode_create_and_check_generic_types
            ( t1, t2, generic_types, tnode_types_are_identical, ex );
    }

    if( t1->kind == TK_COMPOSITE && t2->kind == TK_COMPOSITE ) {
	if( (t1->element_type && t1->element_type->kind == TK_PLACEHOLDER) &&
	    (t2->element_type && t2->element_type->kind == TK_PLACEHOLDER) ) {
	    return (!t1->name || !t2->name ||
		    strcmp( t1->name, t2->name ) == 0);
	} else {
	    return (!t1->name || !t2->name || strcmp( t1->name, t2->name ) == 0) &&
		/* tnode_types_are_identical( t1->element_type, t2->element_type ); */
		tnode_types_are_assignment_compatible
                ( t1->element_type, t2->element_type, generic_types, ex );
	}
    }

    if( t1->kind == TK_FUNCTION_REF && t2->kind == TK_FUNCTION ) {
	return tnode_generic_function_prototypes_match( t1, t2, generic_types,
                                                        NULL, 0, ex );
    }

    if( t1->name && t2->name ) return 0;

    if( t1->kind == TK_FUNCTION_REF && t2->kind == TK_FUNCTION_REF ) {
	return tnode_generic_function_prototypes_match( t1, t2, generic_types,
                                                        NULL, 0, ex );
    }

    if( t1->kind == TK_ARRAY && t2->kind == TK_ARRAY ) {
	if( t1->element_type == NULL ) {
	    return t2->kind == TK_ARRAY;
	} else {
	    return tnode_types_are_assignment_compatible
                ( t1->element_type, t2->element_type, generic_types, ex );
	}
    }

    if( t1->kind == TK_STRUCT && t2->kind == TK_STRUCT ) {
	return tnode_structures_are_compatible( t1, t2, generic_types, ex );
    }
    return 0;
}

static TNODE *tnode_placeholder_implementation( TNODE *abstract,
                                                TNODE *concrete,
                                                TYPETAB *generic_types,
                                                cexception_t *ex )
{
    if( generic_types && abstract->kind == TK_PLACEHOLDER ) {
        TNODE *volatile placeholder_implementation =
            typetab_lookup( generic_types, abstract->name );

        if( !placeholder_implementation ) {
            cexception_t inner;
            cexception_guard( inner ) {
                placeholder_implementation =
                    new_tnode_placeholder( abstract->name, ex );
                tnode_insert_base_type( placeholder_implementation,
                                        share_tnode( concrete ));
                placeholder_implementation =
                    typetab_insert( generic_types, abstract->name,
                                    placeholder_implementation, &inner );
            }
            cexception_catch {
                delete_tnode( placeholder_implementation );
                cexception_reraise( inner, ex );
            }
        }
        return placeholder_implementation;
    }
    return abstract;
}

static int tnode_function_arguments_match_msg( TNODE *f1, TNODE *f2,
                                               TYPETAB *generic_types,
					       char *msg, int msglen,
                                               cexception_t *ex )
{
    DNODE *f1_arg, *f2_arg;
    int narg = 0;

    assert( f1 );
    assert( f2 );
    f1_arg = tnode_arg_prev( f1, NULL );
    f2_arg = tnode_arg_prev( f2, NULL );
    while( f1_arg && f2_arg ) {
	TNODE *f1_arg_type = dnode_type( f1_arg );
	TNODE *f2_arg_type = dnode_type( f2_arg );

        if( f1_arg_type->kind == TK_PLACEHOLDER ) {
            f1_arg_type =
                tnode_placeholder_implementation( f1_arg_type, f2_arg_type,
                                                  generic_types, ex );
        }

	narg++;
	if( !tnode_types_are_identical( f1_arg_type, f2_arg_type,
					generic_types, ex )) {
	    if( msg ) {
		snprintf( msg, msglen, "old prototype argument %d has "
			  "type %s, but new prototype has type %s", narg,
			  tnode_name( f1_arg_type ),
			  tnode_name( f2_arg_type ));
	    }
	    return 0;
	}
	f1_arg = tnode_arg_prev( f1, f1_arg );
	f2_arg = tnode_arg_prev( f2, f2_arg );
    }
    if( f1_arg || f2_arg ) {
	if( msg ) {
	    snprintf( msg, msglen, "new prototype has too %s arguments",
		      f2_arg ? "many" : "little" );
	}
	return 0;
    }
    return 1;
}

static int tnode_function_retvals_match_msg( TNODE *f1, TNODE *f2,
                                             TYPETAB *generic_types,
					     char *msg, int msglen,
					     cexception_t *ex )
{
    DNODE *f1_retval, *f2_retval;
    int nretval = 0;

    assert( f1 );
    assert( f2 );

    f1_retval = tnode_retval_next( f1, NULL );
    f2_retval = tnode_retval_next( f2, NULL );
    while( f1_retval && f2_retval ) {
	TNODE *f1_retval_type = dnode_type( f1_retval );
	TNODE *f2_retval_type = dnode_type( f2_retval );
	char pad[20];

	nretval++;
	if( !tnode_types_are_identical( f1_retval_type, f2_retval_type,
					generic_types, ex )) {
	    if( msg ) {
		int retval_count1 = tnode_retval_nr( f1 );
		int retval_count2 = tnode_retval_nr( f2 );
		int retval_count = retval_count1 > retval_count2 ?
		    retval_count1 : retval_count2;

		snprintf( pad, sizeof(pad), " %d", nretval );
		snprintf( msg, msglen, "old prototype return value%s has "
			  "type %s, but new prototype has type %s",
			  (retval_count < 2 ? "" : pad),
			  tnode_name( f1_retval_type ),
			  tnode_name( f2_retval_type ));
	    }
	    return 0;
	}
	f1_retval = tnode_retval_next( f1, f1_retval );
	f2_retval = tnode_retval_next( f2, f2_retval );
    }
    if( f1_retval || f2_retval ) {
	if( msg ) {
	    snprintf( msg, msglen, "new prototype has too %s return values",
		      f2_retval ? "many" : "little" );
	}
	return 0;
    }
    return 1;
}

static int tnode_generic_function_prototypes_match( TNODE *f1, TNODE *f2,
                                                    TYPETAB *generic_types,
                                                    char *msg, int msglen,
                                                    cexception_t *ex )
{
    return
	tnode_function_arguments_match_msg( f1, f2, generic_types,
                                            msg, msglen, ex ) &&
	tnode_function_retvals_match_msg( f1, f2, generic_types, msg, msglen, ex );
}

int tnode_function_prototypes_match_msg( TNODE *f1, TNODE *f2,
					 char *msg, int msglen )
{
    return 
        tnode_generic_function_prototypes_match( f1, f2,
                                                 NULL, /* generic_types, */
                                                 msg, msglen,
                                                 NULL /* cexception_t *ex */ );
}

int tnode_function_prototypes_match( TNODE *f1, TNODE *f2 )
{
    return tnode_function_prototypes_match_msg( f1, f2, NULL, 0 );
}

static TNODE *tnode_insert_single_enum_value( TNODE* tnode, DNODE *field )
{
    assert( tnode );
    tnode_check_field_does_not_exist( tnode, tnode->fields, "enumerator value",
				      field );
    tnode->fields = dnode_append( field, tnode->fields );
    return tnode;
}

#define STRUCT_FIELD_SIZE sizeof(stackcell_t)

TNODE *tnode_insert_fields( TNODE* tnode, DNODE *field )
{
    TNODE *field_type;
    DNODE *current;
    type_kind_t field_kind;
    char *name;
    size_t field_size;

    assert( tnode );
    tnode_check_field_does_not_exist( tnode, tnode->fields, "field", field );

    foreach_dnode( current, field ) {
	field_type = dnode_type( current );
	field_kind = field_type ? tnode_kind( field_type ) : TK_NONE;
	name = field_type ? tnode_name( field_type ) : NULL;
	field_size = sizeof(stackcell_t);

	if( field_kind != TK_FUNCTION ) {
	    dnode_set_offset( current, tnode->size );
	    tnode->size += STRUCT_FIELD_SIZE;
            tnode_set_flags( tnode, TF_IS_REF );
	    if( field_type && ( tnode_is_reference( field_type ) ||
                                field_type->kind == TK_PLACEHOLDER )) {
		tnode->nrefs = tnode->size / STRUCT_FIELD_SIZE;
	    }
	}
    }

    tnode->fields = dnode_append( tnode->fields, field );

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
	inherited_method = tnode->base_type ? 
	    tnode_lookup_method( tnode->base_type, method_name ) : NULL;

	if( inherited_method ) {
	    if( !dnode_function_prototypes_match_msg( inherited_method, method,
						      msg, sizeof(msg))) {
		yyerrorf( "Prototype of method %s() does not match "
			  "inherted definition:\n%s", dnode_name( method ),
			  msg );
	    }

	    method_offset = dnode_offset( inherited_method );
	} else {
	    tnode->max_vmt_offset++;
	    method_offset = tnode->max_vmt_offset;
	}

        tnode_set_flags( tnode, TF_IS_REF );
	tnode->methods = dnode_append( method, tnode->methods );
	dnode_set_offset( method, method_offset );
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
	tnode->max_vmt_offset = base_type->max_vmt_offset;
	tnode->size += tnode_size( base_type );
	tnode->nrefs += base_type->nrefs;
	foreach_dnode( field, tnode->fields ) {
	    TNODE *field_type = dnode_type( field );
	    type_kind_t field_kind =
		field_type ? tnode_kind( field_type ) : TK_NONE;
	    if( field_kind != TK_FUNCTION ) {
		dnode_set_offset( field,
				  dnode_offset( field ) +
                                  tnode_size( base_type ));
	    }
	}
    }

    return tnode;
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

TNODE *tnode_insert_function_parameters( TNODE* tnode, DNODE *parameters )
{
    assert( tnode );
    assert( !tnode->args );
    tnode->args = parameters;
    return tnode;
}

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
    if( tnode )
	return ( tnode->flags & TF_NON_NULL ) != 0;
    else
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
        tnode->attr_size = attr_value;
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

TNODE *tnode_next( TNODE* list )
{
    if( !list ) return NULL;
    else return list->next;
}
