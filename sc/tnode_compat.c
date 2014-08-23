/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <tnode_compat.h>

/* uses: */
#include <tnode.ci>
#include <string.h>
#include <stdio.h>
#include <assert.h>

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

static int
tnode_implements_interface( TNODE *class_tnode, TNODE *interface_tnode )
{
    TLIST *curr;

    assert( class_tnode );
    foreach_tlist( curr, class_tnode->interfaces ) {
        TNODE *curr_tnode = tlist_data( curr );
        if( curr_tnode == interface_tnode ) {
            return 1;
        }
    }
    return 0;
}

static int
tnode_check_type_identity( TNODE *t1, TNODE *t2,
                           TYPETAB *generic_types,
                           cexception_t *ex )
{
    if( !t1 || !t2 ) return 0;
    if( t1 == t2 ) return 1;
    if( t1->kind == TK_IGNORE || t2->kind == TK_IGNORE ) {
	return 1;
    }

    if( t1->kind == TK_TYPE_DESCR ) {
	return t2->kind == TK_TYPE_DESCR;
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
    if( t1->kind == TK_INTERFACE && t2->kind == TK_CLASS ) {
	return tnode_implements_interface( t2, t1 );
    }
    if( t1->kind == TK_OPERATOR && t2->kind == TK_OPERATOR ) {
        return
	    dnode_lists_are_type_identical( t1->args, t2->args,
					    generic_types, ex ) &&
	    dnode_lists_are_type_identical( t1->return_vals,
					    t2->return_vals,
					    generic_types, ex );
    }

    if( t1->kind == TK_PLACEHOLDER || t2->kind == TK_PLACEHOLDER ) {
        if( generic_types ) {
            return tnode_create_and_check_generic_types
                ( t1, t2, generic_types, tnode_types_are_identical, ex );
        } else {
            return 0;
        }
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

int tnode_types_are_identical( TNODE *t1, TNODE *t2,
			       TYPETAB *generic_types,
			       cexception_t *ex )
{
    if( !t1 || !t2 ) return 0;
    if( t1 == t2 ) return 1;
    if( t1->kind == TK_IGNORE || t2->kind == TK_IGNORE ) {
	return 1;
    }

    if( tnode_is_non_null_reference( t1 ) !=
        tnode_is_non_null_reference( t2 )) {
        return 0;
    }

    return tnode_check_type_identity( t1, t2, generic_types, ex );
}

int tnode_types_are_compatible( TNODE *t1, TNODE *t2,
				TYPETAB *generic_types,
				cexception_t *ex )
{
    if( !t1 || !t2 ) return 0;

    if( tnode_is_non_null_reference( t1 )) {
        if( !tnode_is_non_null_reference( t2 )) {
            return 0;
        }
    }

    if( t1->kind == TK_TYPE_DESCR ) {
	return t2->kind == TK_TYPE_DESCR;
    }
    if( t1->kind == TK_TYPE_DESCR ) {
	return t2->kind == TK_TYPE_DESCR;
    }
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

    return tnode_check_type_identity( t1, t2, generic_types, ex );
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

    if( t1->kind == TK_TYPE_DESCR ) {
	return t2->kind == TK_TYPE_DESCR;
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

    if( t1->kind == TK_INTERFACE && t2->kind == TK_CLASS ) {
	return tnode_implements_interface( t2, t1 );
    }

    if( t1->kind == TK_PLACEHOLDER || t2->kind == TK_PLACEHOLDER ) {
        if( generic_types ) {
            return tnode_create_and_check_generic_types
                ( t1, t2, generic_types, tnode_types_are_identical, ex );
        } else {
            return 0;
        }
    }

    if( t1->kind == TK_COMPOSITE && t2->kind == TK_COMPOSITE ) {
	if( (t1->element_type && t1->element_type->kind == TK_PLACEHOLDER) &&
	    (t2->element_type && t2->element_type->kind == TK_PLACEHOLDER) ) {
	    return (!t1->name || !t2->name ||
		    strcmp( t1->name, t2->name ) == 0);
	} else {
            if( t2->element_type &&
                t2->element_type->kind == TK_PLACEHOLDER &&
                t1->base_type ) {
                return
                    tnode_types_are_assignment_compatible
                    ( t1->base_type, t2, generic_types, ex );                
            } else {
                return (!t1->name || !t2->name ||
                        strcmp( t1->name, t2->name ) == 0) &&
                    /* tnode_types_are_identical( t1->element_type,
                       t2->element_type ); */
                    tnode_types_are_assignment_compatible
                    ( t1->element_type, t2->element_type, generic_types, ex );
            }
        }
    }

    if( t1->kind == TK_FUNCTION_REF && 
        (t2->kind == TK_FUNCTION || t2->kind == TK_CLOSURE )) {
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

static int tnode_retval_nr( TNODE *tnode )
{
    if( tnode->return_vals == NULL ) return 0;
    else return dnode_list_length( tnode->return_vals );
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