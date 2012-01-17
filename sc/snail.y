/*-------------------------------------------------------------------------*\
* $Author$
* $Date$ 
* $Revision$
* $URL$
\*-------------------------------------------------------------------------*/

%{
/* exports: */
#include <snail_y.h>

/* uses: */
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <ctype.h>
#include <dlfcn.h>
#include <cexceptions.h>
#include <cxprintf.h>
#include <allocx.h>
#include <stringx.h>
#include <stdiox.h>
#include <tcodes.h>
#include <thrcode.h>
#include <thrlist.h>
#include <tnode.h>
#include <anode.h>
#include <enode.h>
#include <elist.h>
#include <dlist.h>
#include <tlist.h>
#include <vartab.h>
#include <typetab.h>
#include <symtab.h>
#include <stlist.h>
#include <fixup.h>
#include <bytecode_file.h> /* for bytecode_file_hdr_t, needed by
			      compiler_native_type_size() */
#include <cvalue_t.h>
#include <snail_flex.h>
#include <yy.h>
#include <alloccell.h>
#include <assert.h>

static char *compiler_version = "0.0";

/* COMPILER_STATE contains necessary compiler state that must be
   saved and restored when include files are processed. */

typedef struct COMPILER_STATE {
    char *filename;
    char *use_package_name;
    FILE *yyin;
    ssize_t line_no;
    ssize_t column_no;
    struct COMPILER_STATE *next;
} COMPILER_STATE;

static void delete_compiler_state( COMPILER_STATE *state )
{
    if( state ) {
	freex( state );
    }
}

static COMPILER_STATE *new_compiler_state( char *filename,
					   char *use_package_name,
					   FILE *file,
					   ssize_t line_no,
					   ssize_t column_no,
					   COMPILER_STATE *next,
					   cexception_t *ex )
{
    COMPILER_STATE * volatile state = callocx( sizeof( *state ), 1, ex );

    state->filename = filename;
    state->use_package_name = use_package_name;
    state->yyin = file;
    state->line_no = line_no;
    state->column_no = column_no;
    state->next = next;

    return state;
}

#define starting_local_offset -1

typedef struct {
    THRCODE *thrcode;  /* thrcode should not be freed in
			  delete_compiler(), it should point either to
			  the same object as main_thrcode or to the
			  same object as function_thrcode; both of
			  these fields should be freed in
			  delete_compiler(). */
    THRCODE *main_thrcode;
    THRCODE *function_thrcode;

    THRLIST *thrstack;

    char *static_data;
    ssize_t static_data_size;
    VARTAB *vartab;   /* declared variables, with scopes */
    VARTAB *consts;   /* declared constants, with scopes */
    TYPETAB *typetab; /* declared types and their scopes */

    STLIST *symtab_stack; /* pushed symbol tables */

    int local_offset;
    int *local_offset_stack;
    int local_offset_stack_size;

    /* the addr_stack is an array-used-as-stack and holds entry
       addresses of the loops that are currently being compiled. */
    int addr_stack_size;
    ssize_t *addr_stack;

    /* Paths to search for included files, modules, and libraries: */
    char **include_paths; /* these paths are reused between different
			     compiler instances, can be in the static
			     memory and therefore should not be
			     deleted (freed) in
			     delete_compiler()... */

    /* The following three fields are used to process include files: */
    char *filename;
    FILE *yyin;
    char *use_package_name;
    COMPILER_STATE *include_files;

    DNODE *current_function; /* Function that is currently being
				compiled. NOTE! this field must not be
				deleted in delete_compiler() */

    TNODE *current_type;     /* Type declaration that is currently
				being compiled. NOTE! this field must
				not be deleted in delete_compiler() */

    DNODE *current_call;     /* function call that is currently
				being processed. */
    DLIST *current_call_stack;

    DNODE *current_arg;        /* formal function argument that is currently
				  being processed. NOTE! this field
				  must not be deleted in delete_compiler() */
    DLIST *current_arg_stack;

    /* The enodes in the e_stack mimick the evaluation stack of an
       expression or statement under compilation and hold types of all
       intermediate values. First enode in the list is top of the
       stack. */
    ENODE *e_stack;

    /* the saved_estacks holds stacks of types loaded by the code
       pushed onto the thrstack. */
    ELIST *saved_estacks;

    /* labels and fixups in the 'bytecode' statements: */
    DNODE *bytecode_labels;
    FIXUP *bytecode_fixups;

    /* loop stack for the describing nested loops, needed to implement
       'break' and 'continue' statements: */
    DNODE *loops;

    /* track down exception declared in each module or in the main
       program; start from the beginning in each new module and
       restore the previous value when the compilation of the module
       is finished: */
    int latest_exception_nr;
    int *latest_exception_stack;
    int latest_exception_stack_size;

    /* the following variables describe nesting try{} blocks */
    int try_block_level;
    ssize_t *try_variable_stack;

    /* catch and switch jumpover stack */
    ssize_t catch_jumpover_nr;
    ssize_t *catch_jumpover_stack;
    int catch_jumpover_stack_length;

    /* fields used for the implementation of packages: */
    VARTAB *compiled_packages;
    DLIST *current_package_stack;
    DNODE *current_package; /* this field must not be deleted when deleting
			       COMPILER */
} SNAIL_COMPILER;

static void compiler_drop_include_file( SNAIL_COMPILER *c );

static void delete_snail_compiler( SNAIL_COMPILER *c )
{
    if( c ) {
	while( c->include_files ) {
	    compiler_drop_include_file( c );
	}
	freex( c->filename );
	if( c->yyin ) fclosex( c->yyin, NULL );

        delete_thrcode( c->main_thrcode );
        delete_thrcode( c->function_thrcode );

        delete_thrlist( c->thrstack );

	freex( c->static_data );
	delete_vartab( c->vartab );
	delete_vartab( c->consts );
	delete_vartab( c->compiled_packages );
	delete_typetab( c->typetab );

	delete_stlist( c->symtab_stack );

	delete_dnode( c->bytecode_labels );
	delete_fixup_list( c->bytecode_fixups );

	delete_dnode( c->loops );

        freex( c->local_offset_stack );
	freex( c->addr_stack );
	delete_elist( c->saved_estacks );
	delete_enode( c->e_stack );
	freex( c->latest_exception_stack );
        freex( c->try_variable_stack );

	delete_dnode( c->current_call );

	delete_dlist( c->current_call_stack );
#if 0
        delete_dlist( c->current_arg_stack );
#else
        assert( !c->current_arg_stack );
#endif

	delete_dlist( c->current_package_stack );

        freex( c );
    }
}

static SNAIL_COMPILER *new_snail_compiler( char *filename,
					   char **include_paths,
					   cexception_t *ex )
{
    cexception_t inner;
    SNAIL_COMPILER *cc = callocx( 1, sizeof(SNAIL_COMPILER), ex );

    cexception_guard( inner ) {
	cc->filename = strdupx( filename, &inner );
        cc->main_thrcode = new_thrcode( &inner );
        cc->function_thrcode = new_thrcode( &inner );

	cc->thrcode = cc->function_thrcode;

	thrcode_set_immediate_printout( cc->thrcode, 1 );

	cc->vartab = new_vartab( &inner );
	cc->consts = new_vartab( &inner );
	cc->compiled_packages = new_vartab( &inner );
	cc->typetab = new_typetab( &inner );

	cc->local_offset = starting_local_offset;

	cc->include_paths = include_paths;
    }
    cexception_catch {
        delete_snail_compiler( cc );
        cexception_reraise( inner, ex );
    }
    return cc;
}

static void compiler_save_flex_stream( SNAIL_COMPILER *c, char *filename,
				       cexception_t *ex  )
{
    assert( !c->filename );
    c->filename = strdupx( filename, ex );
    c->yyin = yyin = fopenx( filename, "r", ex );

    snail_flex_push_state( yyin, ex );
    snail_flex_set_current_line_number( 1 );
    snail_flex_set_current_position( 1 );
}

static void compiler_restore_flex_stream( SNAIL_COMPILER *c )
{
    COMPILER_STATE *top;

    top = c->include_files;
    assert( top );

    if( c->yyin ) fclose( c->yyin );
    c->yyin = yyin = top->yyin;
    freex( c->filename );
    c->filename = NULL;

    snail_flex_set_current_line_number( top->line_no );
    snail_flex_set_current_position( top->column_no );
    snail_flex_pop_state();
}

static void compiler_push_compiler_state( SNAIL_COMPILER *c,
					  cexception_t *ex )
{
    COMPILER_STATE *cstate;

    cstate = new_compiler_state( c->filename, c->use_package_name, c->yyin,
				 snail_flex_current_line_number(),
				 snail_flex_current_position(),
				 c->include_files, ex );

    c->filename = NULL;
    c->use_package_name = NULL;
    c->include_files = cstate;
}

void compiler_pop_compiler_state( SNAIL_COMPILER *c )
{
    COMPILER_STATE *top;

    top = c->include_files;
    assert( top );

    freex( c->use_package_name );
    c->use_package_name = top->use_package_name;

    c->include_files = top->next;
    assert( !c->filename );
    c->filename = top->filename;

    delete_compiler_state( top );
}

static char *make_full_file_name( char *filename, char *path,
                                  char *version, cexception_t *ex )
{
    static ssize_t volatile full_path_size;
    static char *volatile full_path;
    ssize_t n;
    ssize_t size;

    if( !filename ) { /* a hack to free memory */
	free( full_path );
	full_path = NULL;
	full_path_size = 0;
	return NULL;
    }

    if( full_path_size == 0 ) {
	size = 50;
	full_path = reallocx( full_path, size, ex );
	full_path_size = size;
    }

    while(1) {
        if( version ) {
            n = snprintf( full_path, full_path_size, "%s/%s/%s",
                          path, version, filename );
        } else {
            n = snprintf( full_path, full_path_size, "%s/%s",
                          path, filename );
        }
	if( n > -1 && n < full_path_size ) {
	    return full_path;
	}
	if( n > -1 ) {
	    size = n + 1;
	} else {
	    size = full_path_size * 2;
	}
	full_path = reallocx( full_path, size, ex );
	full_path_size = size;
    }
}

static char *compiler_find_include_file( SNAIL_COMPILER *c, char *filename,
					 cexception_t *ex )
{
    char **path;
    char *full_path;
    char *version = compiler_version;

    assert( c );

    if( !filename ) {
	return make_full_file_name( NULL, NULL, NULL, ex );
    }

    if( !c->include_paths ) {
	return filename;
    } else {
	for( path = c->include_paths; *path != NULL; path ++ ) {
	    FILE *f;
            /* first, check a compiler version-specific library: */
	    full_path = make_full_file_name( filename, *path, version, ex );
	    f = fopen( full_path, "r" );
	    if( f ) {
		fclose( f );
		/* printf( "Found '%s'\n", full_path ); */
		return full_path;
	    }
            /* if no luck, check for a generic library: */
	    full_path = make_full_file_name( filename, *path, NULL, ex );
	    f = fopen( full_path, "r" );
	    if( f ) {
		fclose( f );
		/* printf( "Found '%s'\n", full_path ); */
		return full_path;
	    }
	}
	make_full_file_name( NULL, NULL, NULL, ex );
	return filename;
    }
}

static void compiler_open_include_file( SNAIL_COMPILER *c, char *filename,
					cexception_t *ex )
{
    char *full_name = compiler_find_include_file( c, filename, ex);
    compiler_push_compiler_state( c, ex );
    compiler_save_flex_stream( c, full_name, ex );
}

static void compiler_push_symbol_tables( SNAIL_COMPILER *c,
					 cexception_t *ex )
{
    SYMTAB *symtab = new_symtab( c->vartab, c->consts, c->typetab, ex );
    stlist_push_symtab( &c->symtab_stack, &symtab, ex );

    c->vartab = new_vartab( ex );
    c->consts = new_vartab( ex );
    c->typetab = new_typetab( ex );
}

static void compiler_use_exported_package_names( SNAIL_COMPILER *c,
						 DNODE *module,
						 cexception_t *ex )
{
    assert( module );

    /* printf( "importing package '%s'\n", dnode_name( module )); */

    vartab_copy_table( c->vartab, dnode_vartab( module ), ex );
    vartab_copy_table( c->consts, dnode_constants_vartab( module ), ex );
    typetab_copy_table( c->typetab, dnode_typetab( module ), ex );
}

static void compiler_pop_symbol_tables( SNAIL_COMPILER *c )
{
    SYMTAB *symtab = stlist_pop_data( &c->symtab_stack );

    if( symtab ) {
	delete_vartab( c->vartab );
	delete_vartab( c->consts );
	delete_typetab( c->typetab );

	obtain_tables_from_symtab( symtab, &c->vartab, &c->consts,
				   &c->typetab );

	delete_symtab( symtab );
    }
}

static void compiler_drop_include_file( SNAIL_COMPILER *c )
{
    compiler_restore_flex_stream( c );
    compiler_pop_compiler_state( c );
}

static void compiler_close_include_file( SNAIL_COMPILER *c,
					 cexception_t *ex )
{
    compiler_restore_flex_stream( c );

    if( c->use_package_name ) {
	DNODE *module = NULL;
	module = vartab_lookup( c->compiled_packages, c->use_package_name );
	if( module ) {
	    /* printf( "module '%s' is being used\n", c->use_package_name ); */
	    compiler_use_exported_package_names( c, module, ex );
	} else {
	    yyerrorf( "no module named '%s'?", c->use_package_name );
	}
    }

    compiler_pop_compiler_state( c );
}

static void push_int( int **array, int *size, int value, cexception_t *ex )
{
    *array = reallocx( *array, ( *size + 1 ) * sizeof(**array), ex );
    (*array)[*size] = value;
    (*size) ++;
}

static int pop_int( int **array, int *size, cexception_t *ex )
{
    (*size) --;
    return (*array)[*size];
}

static void push_ssize_t( ssize_t **array, int *size, ssize_t value,
                          cexception_t *ex )
{
    *array = reallocx( *array, ( *size + 1 ) * sizeof(**array), ex );
    (*array)[*size] = value;
    (*size) ++;
}

static void snail_push_current_address( SNAIL_COMPILER *c, cexception_t *ex )
{
    push_ssize_t( &c->addr_stack, &c->addr_stack_size,
		  thrcode_length(c->thrcode), ex );
}

static ssize_t pop_ssize_t( ssize_t **array, int *size, cexception_t *ex )
{
    (*size) --;
    return (*array)[*size];
}

static ssize_t snail_pop_address( SNAIL_COMPILER *c, cexception_t *ex )
{
    return pop_ssize_t( &c->addr_stack, &c->addr_stack_size, ex );
}

static ssize_t snail_pop_offset( SNAIL_COMPILER *c, cexception_t *ex )
{
    return pop_ssize_t( &c->addr_stack, &c->addr_stack_size, ex )
           - thrcode_length( c->thrcode );
}

static ssize_t snail_code_length( SNAIL_COMPILER *c )
{
    return thrcode_length( c->thrcode );
}

static void snail_push_relative_fixup( SNAIL_COMPILER *c, cexception_t *ex )
{
    thrcode_push_relative_fixup_here( c->thrcode, "", ex );
}

static void snail_push_absolute_fixup( SNAIL_COMPILER *c, cexception_t *ex )
{
    thrcode_push_absolute_fixup_here( c->thrcode, "", ex );
}

static void snail_fixup_here( SNAIL_COMPILER *c )
{
    thrcode_internal_fixup_here( c->thrcode );
}

static void snail_fixup( SNAIL_COMPILER *c, ssize_t value )
{
    thrcode_internal_fixup( c->thrcode, value );
}

static void snail_swap_fixups( SNAIL_COMPILER *c )
{
    thrcode_internal_fixup_swap( c->thrcode );
}

static void compiler_check_enum_basetypes( TNODE *lookup_tnode, TNODE *tnode )
{
    if( tnode && lookup_tnode ) {
	TNODE *base1 = tnode_base_type( lookup_tnode );
	TNODE *base2 = tnode_base_type( tnode );
	char *name = tnode_name( lookup_tnode );

	if( base2 && base1 != base2 ) {
	    if( name ) {
		yyerrorf( "enum type '%s' is being extended with "
			  "wrong parent type", name );
	    } else {
		yyerrorf( "enum type is being extended with "
			  "wrong parent type", name );
	    }
	}
    }
}

static TNODE *snail_typetab_insert_msg( SNAIL_COMPILER *cc,
					char *name,
					type_suffix_t suffix_type,
					TNODE *tnode,
					char *type_conflict_msg,
					cexception_t *ex )
{
    TNODE *lookup_node;

    lookup_node =
	typetab_insert_suffix( cc->typetab, name, suffix_type, tnode, ex );

    if( lookup_node != tnode ) {
	if( tnode_is_forward( lookup_node )) {
	    tnode_shallow_copy( lookup_node, tnode );
	    delete_tnode( tnode );
	} 
	else if( tnode_is_extendable_enum( lookup_node )) {
	    tnode_merge_field_lists( lookup_node, tnode );
	    compiler_check_enum_basetypes( lookup_node, tnode );
	    delete_tnode( tnode );
	} else {
	    char *name = tnode_name( tnode );
	    if( strstr( type_conflict_msg, "%s" ) != NULL ) {
		yyerrorf( type_conflict_msg, name );
	    } else {
		yyerrorf( type_conflict_msg );
	    }
	}
    }
    return lookup_node;
}

static int snail_current_scope( SNAIL_COMPILER *cc )
{
    return vartab_current_scope( cc->vartab );
}

static void snail_typetab_insert( SNAIL_COMPILER *cc,
				  TNODE *tnode,
				  cexception_t *ex )
{
    TNODE *lookup_tnode =
	snail_typetab_insert_msg( cc, tnode_name( tnode ),
				  TS_NOT_A_SUFFIX, tnode,
				  "type '%s' is already declared", ex );
    if( cc->current_package && lookup_tnode == tnode &&
        snail_current_scope( cc )  == 0 ) {
	dnode_typetab_insert_named_tnode( cc->current_package,
					  share_tnode( tnode ), ex );
    }
}

static void snail_vartab_insert_named_vars( SNAIL_COMPILER *cc,
					    DNODE *vars,
					    cexception_t *ex )
{
    vartab_insert_named_vars( cc->vartab, vars, ex );
    if( cc->current_package && dnode_scope( vars ) == 0 ) {
	dnode_vartab_insert_named_vars( cc->current_package,
					share_dnode( vars ), ex );
    }
}

static void snail_consttab_insert_consts( SNAIL_COMPILER *cc, DNODE *consts,
					  cexception_t *ex )
{
    vartab_insert_named_vars( cc->consts, consts, ex );
    if( cc->current_package ) {
	dnode_consttab_insert_consts( cc->current_package,
				      share_dnode( consts ), ex );
    }
}

static void snail_insert_tnode_into_suffix_list( SNAIL_COMPILER *cc,
						 TNODE *tnode,
						 cexception_t *ex )
{
    TNODE *base_type = NULL;
    char *suffix;
    type_kind_t type_kind;
    char *type_conflict_msg = NULL;

    suffix = tnode_suffix( tnode );
    if( !suffix ) suffix = "";

    type_kind = tnode_kind( tnode );

    if( type_kind == TK_SYNONIM &&
	(base_type = tnode_base_type( tnode )) ) {
	type_kind = tnode_kind( base_type );
    }

    switch( type_kind ) {
    case TK_BOOL:
    case TK_INTEGER:
        if( !suffix || suffix[0] == '\0' ) {
	    type_conflict_msg = "integer type with empty suffix is already "
    	    		        "defined in the current scope";
        } else {
	    type_conflict_msg = "integer type with suffix '%s' is already "
    	    		        "defined in the current scope";
	}
	snail_typetab_insert_msg( cc, suffix, TS_INTEGER_SUFFIX, tnode,
				  type_conflict_msg, ex );
	share_tnode( tnode );
	if( cc->current_package ) {
	    dnode_typetab_insert_tnode_suffix( cc->current_package, suffix,
					       TS_INTEGER_SUFFIX,
					       share_tnode( tnode ), ex );
	}
	break;
    case TK_REAL:
        if( !suffix || suffix[0] == '\0' ) {
	    type_conflict_msg = "real type with empty suffix is already "
    	    		        "defined in the current scope";
        } else {
	    type_conflict_msg = "real type with suffix '%s' is already "
    	    		        "defined in the current scope";
	}
	snail_typetab_insert_msg( cc, suffix, TS_FLOAT_SUFFIX, tnode,
				  type_conflict_msg, ex );
	share_tnode( tnode );
	if( cc->current_package ) {
	    dnode_typetab_insert_tnode_suffix( cc->current_package, suffix,
					       TS_FLOAT_SUFFIX,
					       share_tnode( tnode ), ex );
	}
	break;
    case TK_STRING:
        if( !suffix || suffix[0] == '\0' ) {
	    type_conflict_msg = "string type with empty suffix is already "
    	    		        "defined in the current scope";
        } else {
	    type_conflict_msg = "string type with suffix '%s' is already "
    	    		        "defined in the current scope";
	}
	snail_typetab_insert_msg( cc, suffix, TS_STRING_SUFFIX, tnode,
				  type_conflict_msg, ex );
	share_tnode( tnode );
	if( cc->current_package ) {
	    dnode_typetab_insert_tnode_suffix( cc->current_package, suffix,
					       TS_STRING_SUFFIX,
					       share_tnode( tnode ), ex );
	}
	break;
    case TK_NONE:
        if( !suffix || suffix[0] == '\0' ) {
	    type_conflict_msg = "type with empty suffix is already "
    	    		        "defined in the current scope";
        } else {
	    type_conflict_msg = "type with suffix '%s' is already "
    	    		        "defined in the current scope";
	}
	snail_typetab_insert_msg( cc, suffix, TS_NOT_A_SUFFIX, tnode,
				  type_conflict_msg, ex );
	share_tnode( tnode );
	if( cc->current_package ) {
	    dnode_typetab_insert_tnode_suffix( cc->current_package, suffix,
					       TS_NOT_A_SUFFIX,
					       share_tnode( tnode ), ex );
	}
	break;
    case TK_STRUCT:
    case TK_CLASS:
    case TK_BLOB:
    case TK_ARRAY:
    case TK_COMPOSITE:
    case TK_ENUM:
    case TK_REF:
    case TK_FUNCTION_REF:
    case TK_SYNONIM:
	break;
    default:
	yyerrorf( "types of kind '%s' do not have suffix table",
		  tnode_kind_name( tnode ));
	break;
    }
}

static void snail_push_type( SNAIL_COMPILER *c, TNODE *tnode,
			     cexception_t *ex )
{
    ENODE *expr_enode = NULL;

    expr_enode = new_enode_typed( tnode, ex );
    enode_list_push( &c->e_stack, expr_enode );
}

static void snail_push_error_type( SNAIL_COMPILER *c,
				   cexception_t *ex )
{
    ENODE *expr_enode = NULL;

    expr_enode = new_enode( ex );
    enode_set_has_errors( expr_enode );
    enode_list_push( &c->e_stack, expr_enode );
}

static void snail_append_expression_type( SNAIL_COMPILER *c,
					  TNODE *base_tnode )
{
    assert( c->e_stack );
    enode_append_element_type( c->e_stack, base_tnode );
}

static TNODE *new_tnode_array_snail( TNODE *element_type,
				     TYPETAB *typetab,
				     cexception_t *ex )
{
    TNODE *base_type = share_tnode( typetab_lookup( typetab, "array" ));
    return new_tnode_array( element_type, base_type, ex );
}

static TNODE *new_tnode_blob_snail( TYPETAB *typetab, cexception_t *ex )
{
    TNODE *base_type = share_tnode( typetab_lookup( typetab, "blob" ));
    return new_tnode_blob( base_type, ex );
}

static void snail_compile_exception( SNAIL_COMPILER *c,
				     char *exception_name,
				     ssize_t exception_nr,
				     cexception_t *ex )
{
    cexception_t inner;
    TNODE *exception_type =
	share_tnode( typetab_lookup( c->typetab, "exception" ));
    DNODE * volatile exception = NULL;

    cexception_guard( inner ) {
	exception =
	    new_dnode_exception( exception_name, exception_type, &inner );

	dnode_set_ssize_value( exception, exception_nr );
	vartab_insert_named( c->vartab, exception, &inner );
    }
    cexception_catch {
	delete_dnode( exception );
	cexception_reraise( inner, ex );
    }
}

static void snail_compile_next_exception( SNAIL_COMPILER *c,
					  char *exception_name,
					  cexception_t *ex )
{
    snail_compile_exception( c, exception_name, ++c->latest_exception_nr, ex );
}

static void snail_push_array_of_type( SNAIL_COMPILER *c, TNODE *tnode,
				      cexception_t *ex )
{
    cexception_t inner;
    ENODE *expr_enode = NULL;
    TNODE * volatile array_type = NULL;

    cexception_guard( inner ) {
	array_type = new_tnode_array_snail( tnode, c->typetab, &inner );
	share_tnode( tnode );
	expr_enode = new_enode_typed( array_type, &inner );
	enode_list_push( &c->e_stack, expr_enode );
    }
    cexception_catch {
	delete_tnode( array_type );
	cexception_reraise( inner, ex );
    }
}

static void compiler_drop_top_expression( SNAIL_COMPILER *cc )
{
    enode_list_drop( &cc->e_stack );
}

static void compiler_swap_top_expressions( SNAIL_COMPILER *cc )
{
    ENODE *e1 = enode_list_pop( &cc->e_stack );
    ENODE *e2 = enode_list_pop( &cc->e_stack );

    enode_list_push( &cc->e_stack, e1 );
    enode_list_push( &cc->e_stack, e2 );    
}

static void snail_check_and_remove_index_type( SNAIL_COMPILER *cc )
{
    ENODE *idx_enode;

    idx_enode = enode_list_pop( &cc->e_stack );
    delete_enode( idx_enode );
}

static void tnode_report_missing_operator( TNODE *tnode,
					   const char *operator_name,
					   int arity )
{
    char *arity_name = "";
    char pad[80];
    char *type_name;

    if( !tnode ) return;

    type_name = tnode_name( tnode );

    if( arity > 0 ) {
	switch( arity ) {
	    case 1: arity_name = "unary ";  break;
	    case 2: arity_name = "binary "; break;
	    case 3: arity_name = "ternary "; break;
	    default:
		memset( pad, 0, sizeof( pad ));
		snprintf( pad, sizeof(pad)-1, "arity %d ", arity );
		arity_name = pad;
		break;
	}
    }

    if( type_name ) {
	yyerrorf( "type '%s' has no %soperator named '%s'", type_name,
		  arity_name, operator_name );
    } else {
	yyerrorf( "this type has no %soperator named '%s'",
		  arity_name, operator_name );
    }
}

static void snail_emit( SNAIL_COMPILER *cc,
			cexception_t *ex,
			const char *format, ... )
{
    cexception_t inner;
    va_list ap;

    va_start( ap, format );
    cexception_guard( inner ) {
	thrcode_emit_va( cc->thrcode, &inner, format, ap );
    }
    cexception_catch {
	int code = cexception_error_code( &inner );
	const void *tag = cexception_subsystem_tag( &inner );
	if( code == THRCODE_UNRECOGNISED_OPCODE && tag == thrcode_subsystem ) {
	    yyerrorf( (char*)cexception_message( &inner ));
	} else {
	    va_end( ap );
	    cexception_reraise( inner, ex );
	}
    }
    va_end( ap );
}

typedef struct {
    char *key;
    ssize_t val;
} key_value_t;

static ssize_t lookup_ssize_value( key_value_t *dict, char *name )
{
    key_value_t *curr = dict;

    while( curr && curr->key ) {
	if( strcmp( curr->key, name ) == 0 ) {
	    return curr->val;
	}
	curr ++;
    }

    yyerrorf( "keyword '%%%%%s' is not available here", name );

    if( dict && dict->key ) {
	fprintf( stderr, "available keywords are:\n" );
	for( curr = dict; curr && curr->key; curr ++ ) {
	    fprintf( stderr, "'%%%%%s'\n", curr->key );
	}
    } else {
	fprintf( stderr, "keyword table is empty at this point\n" );
    }

    return 0;
}

static key_value_t *make_tnode_key_value_list( TNODE *tnode )
{
    static key_value_t empty_list[1] = {{ NULL }};
    static key_value_t list[] = {
	{ "element_nref" },
	{ NULL },
    };

    if( !tnode ) return empty_list;

    list[0].val = tnode_is_reference( tnode ) ? 1 : 0;

    return list;
}

static key_value_t *make_mdalloc_key_value_list( TNODE *tnode, ssize_t level )
{
    static key_value_t empty_list[1] = {{ NULL }};
    static key_value_t list[] = {
	{ "element_nref" },
	{ "level" },
	{ NULL },
    };

    if( !tnode ) return empty_list;

    list[0].val = tnode_is_reference( tnode ) ? 1 : 0;
    list[1].val = level;

    return list;
}

static void snail_fixup_inlined_function( SNAIL_COMPILER *cc,
					  DNODE *function,
					  key_value_t *fixup_values,
					  ssize_t code_start )
{
    FIXUP *fixup, *fixup_list;

    assert( function );
    fixup_list = dnode_code_fixups( function );

    foreach_fixup( fixup, fixup_list ) {
	char *name = fixup_name( fixup );
	ssize_t value = lookup_ssize_value( fixup_values, name );
	thrcode_fixup_offsetted( cc->thrcode, fixup, code_start, value );
    }
}

static void snail_emit_function_call( SNAIL_COMPILER *cc,
				      DNODE *function,
				      key_value_t *fixup_values,
				      char *trailer,
				      cexception_t *ex )
{
    int is_bytecode = dnode_has_flags( function, DF_BYTECODE );

    if( dnode_has_flags( function, DF_INLINE )) {
	ssize_t code_length, i;
	thrcode_t *code = dnode_code( function, &code_length );
	ssize_t code_start = thrcode_length( cc->thrcode );

	if( code_length > 0 ) {
	    if( !is_bytecode ) {
		snail_emit( cc, ex, "\tc\n", PUSHFRM );
	    }
	    thrcode_emit( cc->thrcode, ex, "\t" );
	    for( i = 0; i < code_length; i++ ) {
		if( code[i].ssizeval > 1000 ) {
		    thrcode_emit( cc->thrcode, ex, "c", code[i].fn );
		} else {
		    thrcode_emit( cc->thrcode, ex, "e", &code[i].ssizeval );
		}
	    }
	    if( trailer && trailer[0] != '\0' ) {
		thrcode_emit( cc->thrcode, ex, trailer );
	    }
	    if( !is_bytecode ) {
		snail_emit( cc, ex, "\n\tc\n", POPFRM );
	    }
	}
	if( fixup_values ) {
	    snail_fixup_inlined_function( cc, function, fixup_values,
					  code_start );
	}
    } else {
	TNODE *fn_tnode = function ? dnode_type( function ) : NULL;

	if( fn_tnode && tnode_kind( fn_tnode ) == TK_FUNCTION_REF ) {
	    snail_emit( cc, ex, "\tc\n", ICALL );
	} else if( fn_tnode && tnode_kind( fn_tnode ) == TK_METHOD ) {
	    char *fn_name = dnode_name( function );
	    ssize_t fn_address = dnode_offset( function );
	    ssize_t zero = 0;
	    snail_emit( cc, ex, "\tceeN\n", VCALL,
			&zero, &fn_address, fn_name );
	} else {
	    char *fn_name = dnode_name( function );
	    ssize_t fn_address = dnode_offset( function );
	    ssize_t zero = 0;
	    if( fn_address == 0 && fn_name ) {
		thrcode_push_forward_function( cc->thrcode, fn_name,
					       thrcode_length( cc->thrcode ) + 1,
					       ex );
		snail_emit( cc, ex, "\tceN\n", CALL, &zero, fn_name );
	    } else {
		/* ssize_t code_length = thrcode_length( snail_cc->thrcode ); */
		/* fn_address -= code_length; */
		snail_emit( cc, ex, "\tceN\n", CALL, &fn_address, fn_name );
	    }
	}
    }
}

static void snail_push_function_retvals( SNAIL_COMPILER *cc, DNODE *function,
                                         TYPETAB *generic_types,
					 cexception_t *ex )
{
    cexception_t inner;
    TNODE *function_tnode;
    DNODE *retval_dnode, *function_retvals;
    TNODE *volatile retval_tnode = NULL;
    ENODE *volatile retval_enode = NULL;

    function_tnode = dnode_type( function );
    function_retvals = tnode_retvals( function_tnode );

    cexception_guard( inner ) {
        foreach_dnode( retval_dnode, function_retvals ) {
            retval_tnode = new_tnode_implementation( dnode_type( retval_dnode ),
                                                     generic_types, &inner );
            retval_enode = new_enode_return_value( retval_tnode, &inner );
            enode_list_push( &cc->e_stack, retval_enode );
            retval_tnode = NULL;
            retval_enode = NULL;
        }
    }
    cexception_catch {
        delete_tnode( retval_tnode );
        delete_enode( retval_enode );
        cexception_reraise( inner, ex );
    }
}

static void snail_compile_return( SNAIL_COMPILER *cc,
				  int nretvals,
				  cexception_t *ex )
{
    int i;
    DNODE *function = cc ? cc->current_function : NULL;
    TNODE *fn_type = function ? dnode_type( function ) : NULL;
    DNODE *fn_retvals = fn_type ? tnode_retvals( fn_type ) : NULL;
    DNODE *retval = NULL;
    ENODE *expr = NULL;

    assert( cc );

    fn_retvals = dnode_list_invert( fn_retvals );
    retval = fn_retvals;
    expr = cc->e_stack;
    for( i = 0; expr && i < nretvals; i++ ) {
	TNODE *available_type;
	TNODE *returned_type;

	if( !retval || enode_is_guarding_retval( expr )) {
	    break;
	}

	returned_type = dnode_type( retval );
	available_type = enode_type( expr );

	/* if( !tnode_types_are_identical( returned_type, available_type )) { */
	if( !tnode_types_are_assignment_compatible( returned_type,
						    available_type )) {
	    yyerrorf( "incompatible types of returned value %d "
		      "of function '%s'",
		      nretvals - i, dnode_name( cc->current_function ));
	}

	retval = dnode_next( retval );
	expr = enode_next( expr );
    }
    fn_retvals = dnode_list_invert( fn_retvals );

    if( !cc->current_function ) {
	yyerrorf( "the \"return\" statement should be used only in "
		  "subroutines, not in the main script" );
    } else {
	if( !expr ) {
	    yyerrorf( "too little values on the stack returned "
		      "from function '%s'",
		      dnode_name( cc->current_function ));
	} else {
	    if( !enode_is_guarding_retval( expr )) {
		yyerrorf( "too many values returned from function '%s'",
			  dnode_name( cc->current_function ));
	    } else {
		if( retval ) {
		    yyerrorf( "too little values returned from function '%s'",
			      dnode_name( cc->current_function ));
		}
	    }
	}
    }

    while( cc->e_stack && !enode_is_guarding_retval( cc->e_stack )) {
	compiler_drop_top_expression( cc );
    }

    if( enode_is_guarding_retval( cc->e_stack )) {
	compiler_drop_top_expression( cc );
    }

    {
	int i;
	for( i = 0; i < cc->try_block_level; i++ ) {
	    snail_emit( cc, ex, "\tc\n", RESTORE );
	}
    }

    if( function && !dnode_has_flags( function, DF_INLINE )) {
	snail_emit( cc, ex, "\tc\n", RET );
    }
}

#define OD_MAGIC 0x12345678

typedef enum {
    ODF_NONE = 0,
    ODF_IS_INHERITED = 0x01,
} operator_description_flags_t;

typedef struct {
    int magic;
    int flags;
    char *name;
    int arity;
    DNODE *operator;
    TNODE *containing_type;
    TNODE *describing_type;
    DNODE *retvals;
    int retval_nr;
} operator_description_t;

static void snail_init_operator_description( operator_description_t *od,
					     TNODE *op_type,
					     char *op_name,
					     int arity )
{
    assert( od );

    memset( od, 0, sizeof(*od) );

    od->magic = OD_MAGIC;
    od->flags = ODF_NONE;
    od->name = op_name;
    od->arity = arity;
    od->containing_type = op_type;
    od->operator = op_type ?
	tnode_lookup_operator_nonrecursive( op_type, op_name, arity )
	: NULL;
    if( !od->operator ) {
	od->operator = op_type ? tnode_lookup_operator( op_type, op_name, arity )
	                         : NULL;
	if( od->operator  ) {
	    od->flags |= ODF_IS_INHERITED;
	}
    }
    od->describing_type = od->operator ? dnode_type( od->operator ) : NULL;
    od->retvals = od->describing_type ?
	tnode_retvals( od->describing_type ) : NULL;
    od->retval_nr = dnode_list_length( od->retvals );
}

static void snail_check_operator_args( SNAIL_COMPILER *cc,
				       operator_description_t *od,
				       TYPETAB *generic_types,
                                       cexception_t *ex )
{
    DNODE *op_args;
    DNODE *arg;
    ENODE *expr;
    int nargs;

    assert( od );
    assert( od->magic == OD_MAGIC );
    assert( cc );
    
    if( od->operator ) {
	op_args = od->describing_type ? tnode_args( od->describing_type ) :
	    NULL;

	expr = cc->e_stack;

	nargs = dnode_list_length( op_args );

	foreach_dnode( arg, op_args ) {
	    TNODE *argument_type;
	    TNODE *expr_type;

	    if( !expr ) {
		yyerrorf( "too little values in the stack for operator '%s'",
			  dnode_name( od->operator ));
		break;
	    }

	    argument_type = dnode_type( arg );
	    expr_type = enode_type( expr );

            if( !tnode_types_are_compatible( argument_type, expr_type,
					     generic_types, ex )) {
	    // if( !tnode_arguments_are_compatible( argument_type, expr_type,
	    //				 generic_types, ex )) {
		yyerrorf( "incompatible type of argument %d for operator '%s'",
			  nargs, dnode_name( od->operator ));
	    }

	    expr = enode_next( expr );
	    nargs --;
	}
    }
}

static void snail_drop_operator_args( SNAIL_COMPILER *cc,
				      operator_description_t *od )
{
    DNODE *op_args;
    DNODE *arg;

    assert( od );
    assert( od->magic == OD_MAGIC );
    assert( cc );
    
    if( od->operator ) {
	op_args = od->describing_type ?
	    tnode_args( od->describing_type ) : NULL;
	foreach_dnode( arg, op_args ) {
	    compiler_drop_top_expression( cc );
	}
    }
}

static void snail_push_operator_retvals( SNAIL_COMPILER *cc,
					 operator_description_t *od,
					 ENODE * volatile *on_error_expr,
                                         TYPETAB *generic_types,
					 cexception_t *ex )
{
    TNODE *retval_type;

    assert( od );
    assert( od->magic == OD_MAGIC );

    retval_type = od->retvals ? dnode_type( od->retvals ) : NULL;

    if( od->containing_type &&
	    ( tnode_kind( od->containing_type ) == TK_SYNONIM ||
	      tnode_kind( od->containing_type ) == TK_ENUM ) &&
	    (od->flags & ODF_IS_INHERITED) != 0 ) {
	TNODE *base_type = tnode_base_type( od->containing_type );
	if( retval_type == base_type ) {
	    retval_type = od->containing_type;
	}
    }

    if( generic_types ) {
    // if( 0 ) {
        // CHECK MEMORY USAGE HERE!!! S.G.
        retval_type = new_tnode_implementation( retval_type, generic_types, ex );
    }

    if( od->containing_type && retval_type &&
        tnode_kind( retval_type ) == TK_PLACEHOLDER ) {
	TNODE *element_type = tnode_element_type( od->containing_type );
	if( element_type ) {
	    retval_type = element_type;
	}
    }

    if( retval_type ) {
	snail_push_type( cc, retval_type, ex );
	share_tnode( retval_type );
    }  else {
	if( !od->operator && on_error_expr && *on_error_expr ) {
	    enode_set_has_errors( *on_error_expr );
	    enode_list_push( &cc->e_stack, *on_error_expr );
	    *on_error_expr = NULL; /* let's not delete expression :) */
	}
    }
}

static void snail_emit_operator_or_report_missing( SNAIL_COMPILER *cc,
						   operator_description_t *od,
						   key_value_t *fixup_values,
						   char *trailer,
						   cexception_t *ex )
{
    assert( od );
    assert( od->magic == OD_MAGIC );

    if( od->operator ) {
	snail_emit_function_call( cc, od->operator, fixup_values, trailer, ex );
    } else {
	tnode_report_missing_operator( od->containing_type,
				       od->name, od->arity );
    }
}

static void snail_check_operator_retvals( SNAIL_COMPILER *cc,
					  operator_description_t *od,
					  int minvals,
					  int maxvals )
{
    assert( od );
    assert( od->magic == OD_MAGIC );

    if( od->operator && !od->describing_type ) {
	yyerrorf( "type '%s' operator '%s' does not have "
		  "an operator type description!",
		  tnode_name(od->containing_type), od->name );
    }

    if( od->describing_type &&
	( od->retval_nr < minvals || od->retval_nr > maxvals )) {
	if( minvals == 1 && maxvals == 1 ) {
	    yyerrorf( "type '%s' operator '%s' should return one value",
		      tnode_name(od->containing_type), od->name );
	} else
	if( minvals == 0 && maxvals == 1 && od->arity == 1 ) {
	    yyerrorf( "currently, unary operators should return no value "
		      "or a single value, but operator '%s' "
		      "returns %d values", od->name, od->retval_nr );
	} else
	if( minvals == maxvals ) {
	    yyerrorf( "operator '%s' should return %d values, but it is "
		      "declared to return %d values",
		      od->name, maxvals, od->retval_nr );
	} else {
	    yyerrorf( "operator '%s' should return no more than %d "
		      "and not less than %d values, but it is declared "
		      "to return %d values",
		      od->name, maxvals, minvals, od->retval_nr );
	}
    }
}

static int compiler_test_top_types_are_identical( SNAIL_COMPILER *cc,
						  cexception_t *ex )
{
    ENODE * expr1 = NULL, * expr2 = NULL;

    assert( cc );

    expr1 = cc->e_stack;
    expr2 = expr1 ? enode_next( expr1 ) : NULL;

    if( !expr1 || !expr2 ) {
	return 0;
    } else {
	TNODE *type1 = enode_type( expr1 );
	TNODE *type2 = enode_type( expr2 );

	if( !tnode_types_are_identical( type1, type2, NULL, ex )) {
	    return 0;
	} else {
	    return 1;
	}
    }    
}

static int snail_test_top_types_are_assignment_compatible(
    SNAIL_COMPILER *cc,
    cexception_t *ex )
{
    ENODE * expr1 = NULL, * expr2 = NULL;

    assert( cc );

    expr1 = cc->e_stack;
    expr2 = expr1 ? enode_next( expr1 ) : NULL;

    if( !expr1 || !expr2 ) {
	return 0;
    } else {
	TNODE *type1 = enode_type( expr1 );
	TNODE *type2 = enode_type( expr2 );

	if( !tnode_types_are_assignment_compatible( type1, type2 )) {
	    return 0;
	} else {
	    return 1;
	}
    }    
}

static int snail_test_top_types_are_readonly_compatible_for_copy(
    SNAIL_COMPILER *cc,
    cexception_t *ex )
{
    ENODE * expr1 = NULL, * expr2 = NULL;

    assert( cc );

    expr1 = cc->e_stack;
    expr2 = expr1 ? enode_next( expr1 ) : NULL;

    if( !expr1 || !expr2 ) {
	return 0;
    } else {
	if( enode_has_flags( expr2, EF_IS_READONLY )) {
	    return 0;
	} else {
	    TNODE *tnode1 = enode_type( expr1 );
	    TNODE *elem_type1 = tnode_element_type( tnode1 );

	    if( !elem_type1 ) {
		return 0;
	    } else
	    if( tnode_is_reference( elem_type1 ) &&
		!tnode_is_immutable( elem_type1 ) &&
		enode_has_flags( expr1, EF_IS_READONLY )) {
		return 0;
	    } else {
		return 1;
	    }
	}
    }
}

static int compiler_check_top_2_expressions_are_identical( SNAIL_COMPILER *cc,
							   char *binop_name,
							   cexception_t *ex )
{
    ENODE * volatile expr1 = NULL, * volatile expr2 = NULL;

    assert( cc );

    expr1 = cc->e_stack;
    expr2 = expr1 ? enode_next( expr1 ) : NULL;

    if( !expr1 || !expr2 ) {
	yyerrorf( "not enough values on the stack "
		  "for binary operator '%s'", binop_name );
	return 0;
    } else {
	TNODE *type1 = enode_type( expr1 );
	TNODE *type2 = enode_type( expr2 );

	if( strcmp( binop_name, "%%" ) != 0 && 
	    !tnode_types_are_identical( type1, type2, NULL, ex )) {
	    yyerrorf( "incompatible types for binary operator '%s'",
		      binop_name );
	    return 0;
	}
	return 1;
    }
}

static void compiler_check_top_2_expressions_and_drop( SNAIL_COMPILER *cc,
						       char *binop_name,
						       cexception_t *ex )
{
    compiler_check_top_2_expressions_are_identical( cc, binop_name, ex );
    compiler_drop_top_expression( cc );
}

/*
  NB: on function naming:

  functions that are called ..._emit_...() just emit bytecode
  operators and do not modify type stack; on the contrary
  ..._compile_...() functions both generate code and adjust type
  stack.

  Consequence: "compile" functions can (and do) call "emit" functions,
  but not the other way round.

  Saulius Grazulis 2006.08.14 (Orenburg)

*/

static void snail_compile_binop( SNAIL_COMPILER *cc,
				 char *binop_name,
				 cexception_t *ex )
{
    cexception_t inner;
    ENODE * expr1 = NULL, * expr2 = NULL;
    ENODE * volatile top1 = NULL, * volatile top2 = NULL;
    int stack_is_ok;
    TYPETAB *volatile generic_types = NULL;

    expr1 = cc->e_stack;
    expr2 = expr1 ? enode_next( expr1 ) : NULL;

    stack_is_ok =
	compiler_check_top_2_expressions_are_identical( cc, binop_name, ex );

    generic_types = new_typetab( ex );
    cexception_guard( inner ) {
	if( expr1 && expr2 ) {
	    TNODE *type1 = enode_type( expr1 );
	    operator_description_t od;

	    snail_init_operator_description( &od, type1, binop_name, 2 );
	    if( !od.operator ) {
		TNODE *type2 = enode_type( expr2 );
		snail_init_operator_description( &od, type2, binop_name, 2 );
	    }

	    if( stack_is_ok ) {
		snail_check_operator_args( cc, &od, generic_types, &inner );
	    }

	    top1 = enode_list_pop( &cc->e_stack );
	    top2 = enode_list_pop( &cc->e_stack );

	    snail_emit_operator_or_report_missing( cc, &od, NULL, "\n",
                                                   &inner );
	    snail_check_operator_retvals( cc, &od, 1, 1 );
	    snail_push_operator_retvals( cc, &od, &top2, generic_types,
                                         &inner );
	}
    }
    cexception_catch {
	delete_enode( top1 );
	delete_enode( top2 );
        delete_typetab( generic_types );
	cexception_reraise( inner, ex );
    }
    delete_enode( top1 );
    delete_enode( top2 );
    delete_typetab( generic_types );
}

static key_value_t *make_array_element_key_value_list( TNODE *array )
{
    TNODE *element_type = array ? tnode_element_type( array ) : NULL;

    if( !element_type ) return NULL;

    return make_tnode_key_value_list( element_type );
}

static void snail_compile_unop( SNAIL_COMPILER *cc,
				char *unop_name,
				cexception_t *ex )
{
    cexception_t inner;
    ENODE * volatile expr = cc->e_stack;
    ENODE * volatile top = NULL;
    TYPETAB *volatile generic_types = NULL;

    generic_types = new_typetab( ex );
    cexception_guard( inner ) {
	if( !expr ) {
	    yyerrorf( "not enough values on the stack for unary operator '%s'",
		      unop_name );
	} else {
	    TNODE *expr_type = enode_type( expr );
	    operator_description_t od;
	    key_value_t *fixup_values =
		make_array_element_key_value_list( expr_type );

	    snail_init_operator_description( &od, expr_type, unop_name, 1 );
	    snail_check_operator_args( cc, &od, generic_types, &inner );

	    top = enode_list_pop( &cc->e_stack );

	    snail_emit_operator_or_report_missing( cc, &od, fixup_values,
						   "\n", ex );
	    snail_check_operator_retvals( cc, &od, 0, 1 );
	    snail_push_operator_retvals( cc, &od, &top, generic_types, &inner );
	}
    }
    cexception_catch {
	delete_enode( top );
        delete_typetab( generic_types );
	cexception_reraise( inner, ex );	
    }
    delete_enode( top );
    delete_typetab( generic_types );
}

static void snail_emit_st( SNAIL_COMPILER *cc,
			   TNODE *expr_type,
			   char *var_name,
			   ssize_t var_offset,
			   int var_scope,
			   cexception_t *ex )
{
    operator_description_t od;

    if( var_scope == snail_current_scope( cc )) {

	snail_init_operator_description( &od, expr_type, "st", 1 );
	snail_check_operator_args( cc, &od, NULL /*generic_types*/, ex );

	if( od.operator ) {
	    snail_emit_function_call( cc, od.operator, NULL, "", ex );
	    snail_emit( cc, ex, "eN\n", &var_offset, var_name );
	} else {
	    if( tnode_is_reference( expr_type )) {
		snail_emit( cc, ex, "\tceN\n", PST, &var_offset, var_name );
	    } else {
		snail_emit( cc, ex, "\tceN\n", ST, &var_offset, var_name );
	    }
	}
    } else {
	if( var_scope == 0 ) {
	    snail_init_operator_description( &od, expr_type, "stg", 1 );
	    snail_check_operator_args( cc, &od, NULL /*generic_types*/, ex );

	    if( od.operator ) {
		snail_emit_function_call( cc, od.operator, NULL, "", ex );
		snail_emit( cc, ex, "eN\n", &var_offset, var_name );
	    } else {
		if( tnode_is_reference( expr_type )) {
		    snail_emit( cc, ex, "\tceN\n", PSTG, &var_offset, var_name );
		} else {
		    snail_emit( cc, ex, "\tceN\n", STG, &var_offset, var_name );
		}
	    }
	} else {
	    yyerrorf( "can only store variables in the current scope"
		      "or in the scope 0" );
	}
    }

    snail_check_operator_retvals( cc, &od, 0, 0 );
}

static void snail_compile_type_conversion( SNAIL_COMPILER *cc,
					   char *target_name,
					   cexception_t *ex )
{
    cexception_t inner;
    ENODE * volatile expr = enode_list_pop( &cc->e_stack );
    ENODE * volatile converted_expr = NULL;
    TNODE * expr_type = expr ? enode_type( expr ) : NULL;
    char *source_name = expr_type ? tnode_name( expr_type ) : NULL;

    cexception_guard( inner ) {
	if( !expr ) {
	    yyerrorf( "not enough values on the stack for type conversion "
		      "from '%s' to '%s'", source_name, target_name );
	} else {
	    TNODE *target_type =
		typetab_lookup( cc->typetab, target_name );
	    DNODE *conversion =
		target_type ?
		    tnode_lookup_conversion( target_type, source_name ) :
		    NULL;
	    TNODE *optype = conversion ? dnode_type( conversion ) : NULL;
	    DNODE *retvals = optype ? tnode_retvals( optype ) : NULL;
	    int retval_nr = dnode_list_length( retvals );

	    if( !target_type ) {
		yyerrorf( "type conversion impossible - "
			  "target type '%s' not defined in the current scope",
			  target_name );
	    } else
	    if( !conversion ) {
		if( source_name && target_name ) {
		    yyerrorf( "type '%s' has no conversion from type '%s'",
			      target_name, source_name );
		} else {
		    if( target_name ) {
			yyerrorf( "type '%s' has no conversion from the given "
				  "type",  target_name );
		    } else {
			yyerrorf( "the required type has no conversion from "
				  "the given type" );
		    }
		}
	    } else
	    if( retval_nr != 1 ) {
		yyerrorf( "type conversion operators should return "
			  "a single value, but conversion to from '%s' to '%s' "
			  "returns %d values",
			  target_name, source_name, retval_nr );
	    }
	    if( conversion ) {
		snail_emit_function_call( cc, conversion, NULL, "\n", ex );
	    }

	    if( target_type ) {
		converted_expr = new_enode_typed( target_type, &inner );
		share_tnode( target_type );
		enode_list_push( &cc->e_stack, converted_expr );
		delete_enode( expr );
	    } else {
		enode_list_push( &cc->e_stack, expr );
	    }
	}
    }
    cexception_catch {
	enode_list_push( &cc->e_stack, expr );
	cexception_reraise( inner, ex );
    }
}

static void snail_compile_variable_assignment_or_init(
    SNAIL_COMPILER *cc,
    DNODE *variable,
    int (*enode_is_readonly_compatible)( ENODE *, DNODE * ),
    cexception_t *ex )
{
    ENODE *expr = cc->e_stack;

    if( !expr ) {
	yyerrorf( "not enough values on the stack for assignment to "
		  "variable '%s'", dnode_name( variable ));
    } else {
	TNODE *expr_type = enode_type( expr );

	char *var_name = variable ? dnode_name( variable ) : NULL;
	TNODE *var_type = variable ? dnode_type( variable ) : NULL;
	ssize_t var_offset = variable ? dnode_offset( variable ) : 0;
	int var_scope = variable ? dnode_scope( variable ) : -1;

	/* if( !tnode_types_are_identical( var_type, expr_type )) { */
	if( !tnode_types_are_assignment_compatible( var_type, expr_type )) {
	    char *src_name = expr_type ? tnode_name( expr_type ) : NULL;
	    char *dst_name = var_type ? tnode_name( var_type ) : NULL;
	    if( src_name && dst_name &&
		tnode_lookup_conversion( var_type, src_name )) {
		snail_compile_type_conversion( cc, dst_name, ex );
		expr = cc->e_stack;
		expr_type = enode_type( expr );
		snail_emit_st( cc, expr_type, var_name, var_offset,
			       var_scope, ex );
	    } else {
		if( var_name ) {
		    yyerrorf( "incompatible types for assignment to variable "
			      "'%s'", var_name );
		} else {
		    yyerrorf( "incompatible types for assignment to variable" );
		}
	    }
	} else if( !(*enode_is_readonly_compatible)( expr, variable )) {
	    char *name = variable ? dnode_name( variable ) : NULL;
	    if( dnode_has_flags( variable, DF_IS_READONLY )) {
		if( name ) {
		    yyerrorf( "can not assign to the readonly variable '%s'",
			      name );
		} else {
		    yyerrorf( "can not assign to a readonly variable" );
		}
	    } else {
		if( name ) {
		    yyerrorf( "can not assign readonly content to variable '%s'",
			      name );
		} else {
		    yyerrorf( "can not assign readonly content to this "
			      "variable" );
		}
	    }
	} else {
	    snail_emit_st( cc, expr_type, var_name, var_offset,
			   var_scope, ex );
	}
    }
    compiler_drop_top_expression( cc );
}

static void snail_compile_variable_assignment( SNAIL_COMPILER *cc,
					       DNODE *variable,
					       cexception_t *ex )
{
    snail_compile_variable_assignment_or_init(
        cc, variable, enode_is_readonly_compatible_with_var, ex );
}

static void snail_compile_variable_initialisation( SNAIL_COMPILER *cc,
						   DNODE *variable,
						   cexception_t *ex )
{
    snail_compile_variable_assignment_or_init(
        cc, variable, enode_is_readonly_compatible_for_init, ex );
}

static void snail_compile_store_variable( SNAIL_COMPILER *cc,
					  DNODE *varnode,
					  cexception_t *ex )
{
    if( varnode ) {
        snail_compile_variable_assignment( cc, varnode, ex );
    } else {
        snail_emit( cc, ex, "\tcNN\n", ST, "???", "???" );
    }
}

static void snail_compile_initialise_variable( SNAIL_COMPILER *cc,
					       DNODE *varnode,
					       cexception_t *ex )
{
    if( varnode ) {
        snail_compile_variable_initialisation( cc, varnode, ex );
    } else {
        snail_emit( cc, ex, "\tcNN\n", ST, "???", "???" );
    }
}

static void snail_stack_top_dereference( SNAIL_COMPILER *cc )
{
    if( cc->e_stack ) {
	TNODE *expr_type = enode_type( cc->e_stack );
	if( tnode_kind( expr_type ) != TK_ADDRESSOF ) {
	    yyerror( "only address of some type can be dereferenced" );
	}
	enode_make_type_to_element_type( cc->e_stack );
    } else {
	yyerror( "not enough values on the evaluation stack for "
		 "dereferencing?" );
    }    
}

static int snail_stack_top_is_addressof( SNAIL_COMPILER *cc )
{
    ENODE *enode = cc ? cc->e_stack : NULL;
    TNODE *etype = enode ? enode_type( enode ) : NULL;
#if 1
    return etype ? tnode_is_addressof( etype ) : 0;
#else
    return etype ? tnode_kind( etype ) == TK_ADDRESSOF : 0;
#endif
}

static void snail_compile_ldi( SNAIL_COMPILER *cc, cexception_t *ex )
{
    ENODE * volatile expr;

    expr = cc->e_stack;

    if( !snail_stack_top_is_addressof( cc )) return;

    if( !expr ) {
	yyerrorf( "not enough values on the stack for indirect load (LDI)" );
    } else {
	TNODE *expr_type = enode_type( expr );
	TNODE *element_type =
	    expr_type ? tnode_element_type( expr_type ) : NULL;
	operator_description_t od;

	snail_init_operator_description( &od, element_type, "ldi", 1 );

	if( !expr_type || tnode_kind( expr_type ) != TK_ADDRESSOF ) {
	    yyerrorf( "lvalue is needed for indirect load (LDI)" );
	} else {
	    snail_check_operator_args( cc, &od, NULL /*generic_types*/, ex );
	}

	if( od.operator ) {
	    cexception_t inner;

	    expr = enode_list_pop( &cc->e_stack );
	    cexception_guard( inner ) {
		snail_emit_function_call( cc, od.operator, NULL, "\n", &inner );
		snail_check_operator_retvals( cc, &od, 1, 1 );
		snail_push_operator_retvals( cc, &od, &expr,
                                             NULL /*generic_types*/, &inner );
	    }
	    cexception_catch {
		delete_enode( expr );
		cexception_reraise( inner, ex );
	    }
	    delete_enode( expr );
	} else {
	    TNODE *element_type =
		expr_type ? tnode_element_type( expr_type ) : NULL;

	    if( element_type && tnode_is_reference( element_type )) {
		snail_emit( cc, ex, "\tc\n", PLDI );
	    } else {
		snail_emit( cc, ex, "\tc\n", LDI );
	    }
	    snail_stack_top_dereference( cc );
	}
    }
}

static void snail_compile_sti( SNAIL_COMPILER *cc, cexception_t *ex )
{
    cexception_t inner;
    ENODE *expr = NULL;
    ENODE *lval = NULL;
    ENODE * volatile top1 = NULL;
    ENODE * volatile top2 = NULL;

    expr = cc->e_stack;
    lval = expr ? enode_next( expr ) : NULL;

    cexception_guard( inner ) {
	if( !expr || !lval ) {
	    yyerrorf( "not enough values on the stack for assignment" );
	} else {
	    TNODE *expr_type = enode_type( expr );
	    TNODE *addr_type = enode_type( lval );
	    TNODE *element_type =
		addr_type ? tnode_element_type( addr_type ) : NULL;
	    operator_description_t od;

	    if( element_type && expr_type ) {
		/* if( !tnode_types_are_identical( element_type, expr_type )) {
		 */
		if( !tnode_types_are_assignment_compatible( element_type,
							    expr_type )) {
		    char *src_name = tnode_name( expr_type );
		    char *dst_name = tnode_name( element_type );
		    if( src_name && dst_name &&
			tnode_lookup_conversion( element_type, src_name )) {
			snail_compile_type_conversion( cc, dst_name, ex );
			expr = cc->e_stack;
		    } else {
			yyerrorf( "incompatible types for assignment" );
		    }
		}
	    }

	    if( !enode_is_readonly_compatible_with_expr( expr, lval )) {
		if( enode_has_flags( lval, EF_IS_READONLY )) {
		    yyerrorf( "can not assign to a readonly component" );
		} else {
		    yyerrorf( "can not assign readonly content" );
		}
	    }

	    snail_init_operator_description( &od, expr_type, "sti", 2 );

	    if( !addr_type || tnode_kind( addr_type ) != TK_ADDRESSOF ) {
		yyerrorf( "lvalue is needed for assignment" );
	    } else {
		snail_check_operator_args( cc, &od, NULL /*generic_types*/,
                                           &inner );
	    }

	    top1 = enode_list_pop( &cc->e_stack );
	    top2 = enode_list_pop( &cc->e_stack );

	    if( od.operator ) {
		snail_emit_function_call( cc, od.operator, NULL, "\n", &inner );
		snail_check_operator_retvals( cc, &od, 0, 0 );
	    } else {
		if( expr_type && tnode_is_reference( expr_type )) {
		    snail_emit( cc, &inner, "\tc\n", PSTI );
		} else {
		    snail_emit( cc, &inner, "\tc\n", STI );
		}
	    }
	}
    }
    cexception_catch {
	delete_enode( top1 );
	delete_enode( top2 );
	cexception_reraise( inner, ex );
    }
    delete_enode( top1 );
    delete_enode( top2 );
}

static void compiler_duplicate_top_expression( SNAIL_COMPILER *cc,
					       cexception_t *ex )
{
    ENODE *expr;

    expr = cc->e_stack;

    if( !expr ) {
	yyerrorf( "not enough values on the stack for duplication "
		  "of expression" );
    } else {
	TNODE *expr_type = enode_type( expr );
	snail_push_type( cc, share_tnode( expr_type ), ex );
    }
}

static void snail_compile_operator( SNAIL_COMPILER *cc,
				    TNODE *tnode,
				    char *operator_name,
				    int arity,
				    cexception_t *ex )
{
    operator_description_t od;

    snail_init_operator_description( &od, tnode, operator_name, arity );
    snail_emit_operator_or_report_missing( cc, &od, NULL, "", ex );
    snail_check_operator_retvals( cc, &od, 0, 1 );
    snail_push_operator_retvals( cc, &od, NULL, NULL /* generic_types */, ex );
}

static void snail_check_and_compile_operator( SNAIL_COMPILER *cc,
					      TNODE *tnode,
					      char *operator_name,
					      int arity,
					      key_value_t *fixup_values,
					      cexception_t *ex )
{
    cexception_t inner;
    operator_description_t od;
    TYPETAB *volatile generic_types = NULL;

    generic_types = new_typetab( ex );
    cexception_guard( inner ) {
	snail_init_operator_description( &od, tnode, operator_name, arity );
	snail_check_operator_args( cc, &od, generic_types, ex );
	snail_drop_operator_args( cc, &od );
	snail_emit_operator_or_report_missing( cc, &od, fixup_values, "", ex );
	snail_check_operator_retvals( cc, &od, 0, 1 );
	snail_push_operator_retvals( cc, &od, NULL, generic_types, ex );
    }
    cexception_catch {
	delete_typetab( generic_types );
	cexception_reraise( inner, ex );
    }
    delete_typetab( generic_types );
}

static void snail_check_and_compile_top_operator( SNAIL_COMPILER *cc,
						  char *operator,
						  int arity,
						  cexception_t *ex )
{
    ENODE *expr = cc->e_stack;
    TNODE *tnode = NULL;

    if( !expr ) {
	yyerrorf( "not enough values on the stack for '%s' operator",
		  operator );
    } else 
    if( (tnode = enode_type(expr)) == NULL ){
	yyerrorf( "stack top expression has no type in '%s' operator",
		  operator );
    } else {
	TNODE *left_type = NULL;	
	ENODE *left_expr = expr ? enode_next( expr ) : NULL;
	if( arity > 1 ) {
	    if( left_expr ) {
		left_type = enode_type( left_expr );
	    } else {
		yyerrorf( "no left operand for binary operator '%s'?",
			  operator );
	    }
	}
	snail_check_and_compile_operator( cc, tnode, operator, arity, 
					  /*fixup_values:*/ NULL, ex );
    }
}

static void snail_check_and_compile_top_2_operator( SNAIL_COMPILER *cc,
						    char * operator,
						    int arity,
						    cexception_t *ex )
{
    ENODE *expr = cc->e_stack;
    ENODE *expr2 = cc->e_stack ? enode_next( cc->e_stack ) : NULL;
    TNODE *tnode = NULL;
    TNODE *tnode2 = NULL;

    if( !expr || ! expr2 ) {
	yyerrorf( "not enough values on the stack for '%s' operator "
		  "(need 2 values)", operator );
    } else 
    if( (tnode = enode_type(expr)) == NULL ||
	(tnode2 = enode_type(expr2)) == NULL){
	yyerrorf( "one two stack top expressions has no type "
		  "in '%s' operator", operator );
    } else {
	if( tnode_is_addressof( tnode2 )) {
	    tnode2 = tnode_element_type( tnode2 );
	}
	if( tnode_lookup_operator( tnode2, operator, arity )) {
	    TNODE *element_type = tnode_element_type( tnode2 );
	    key_value_t *fixup_values = element_type ?
		make_tnode_key_value_list( element_type ) : NULL;

	    snail_check_and_compile_operator( cc, tnode2, operator, arity,
					      fixup_values, ex );
	} else {
	    snail_check_and_compile_operator( cc, tnode, operator, arity, 
					      /*fixup_values:*/ NULL, ex );
	}
    }
}

static void snail_compile_dup( SNAIL_COMPILER *cc, cexception_t *ex )
{
    ENODE *expr;

    expr = cc->e_stack;

    if( !expr ) {
	yyerrorf( "not enough values on the stack for duplication (DUP)" );
    } else {
	TNODE *expr_type = enode_type( expr );
	operator_description_t od;

	snail_init_operator_description( &od, expr_type, "dup", 1 );

	if( od.operator ) {
	    ENODE *new_expr = expr;
	    snail_emit_function_call( cc, od.operator, NULL, "\n", ex );
	    snail_check_operator_args( cc, &od, NULL /*generic_types*/, ex );
	    snail_check_operator_retvals( cc, &od, 1, 1 );
	    snail_push_operator_retvals( cc, &od, &new_expr,
                                         NULL /* generic_types */, ex );
	    if( !new_expr ) {
		share_enode( expr );
	    }
	} else {
	    snail_emit( cc, ex, "\tc\n", DUP );
	    snail_push_type( cc, expr_type, ex );
	    share_tnode( expr_type );
	}
    }
}

static int snail_dnode_is_reference( SNAIL_COMPILER *cc, DNODE *dnode )
{
    return dnode ? dnode_type_is_reference( dnode ) : 0;
}

static int snail_stack_top_is_integer( SNAIL_COMPILER *cc )
{
    ENODE *enode = cc ? cc->e_stack : NULL;
    TNODE *etype = enode ? enode_type( enode ) : NULL;
    return etype ? tnode_is_integer( etype ) : 0;
}

static int snail_stack_top_is_reference( SNAIL_COMPILER *cc )
{
    ENODE *enode = cc ? cc->e_stack : NULL;
    TNODE *etype = enode ? enode_type( enode ) : NULL;
    return etype ? tnode_is_reference( etype ) : 0;
}

static int snail_stack_top_base_is_reference( SNAIL_COMPILER *cc )
{
    ENODE *enode = cc ? cc->e_stack : NULL;
    TNODE *etype = enode ? enode_type( enode ) : NULL;
    TNODE *ebase = etype ? tnode_element_type( etype ) : NULL;
    return ebase ? tnode_is_reference( ebase ) : 0;
}
 
static int snail_stack_top_is_array( SNAIL_COMPILER *cc )
{
    ENODE *enode = cc ? cc->e_stack : NULL;
    TNODE *etype = enode ? enode_type( enode ) : NULL;
    return etype ? tnode_kind( etype ) == TK_ARRAY : 0;
}

static int snail_stack_top_has_references( SNAIL_COMPILER *cc,
					   ssize_t drop_retvals )
{
    ssize_t i;
    ENODE *expr = cc->e_stack;

    for( i = 0; i < drop_retvals && expr; i++ ) {
	TNODE *expr_type = enode_type( expr );

	if( expr_type && tnode_is_reference( expr_type )) {
	    return 1;
	}
	expr = enode_next( expr );
    }

    return 0;
}

static void snail_compile_drop( SNAIL_COMPILER *cc, cexception_t *ex )
{
    if( snail_stack_top_is_reference( cc )) {
	snail_emit( cc, ex, "\tc\n", PDROP );
    } else {
	snail_emit( cc, ex, "\tc\n", DROP );
    }
    compiler_drop_top_expression( cc );
}

static void snail_compile_dropn( SNAIL_COMPILER *cc,
				 ssize_t drop_values,
				 cexception_t *ex )
{
    ssize_t i;

    if( snail_stack_top_has_references( cc, drop_values )) {
	snail_emit( cc, ex, "\tce\n", PDROPN, &drop_values );
    } else {
	snail_emit( cc, ex, "\tce\n", DROPN, &drop_values );
    }
    for( i = 0; i < drop_values; i ++ ) {
	compiler_drop_top_expression( cc );
    }
}

static void snail_compile_swap( SNAIL_COMPILER *cc, cexception_t *ex )
{
    ENODE *expr1 = enode_list_pop( &cc->e_stack );
    ENODE *expr2 = enode_list_pop( &cc->e_stack );

    if( !expr1 || !expr2 ) {
	yyerrorf( "not enough values on the stack for SWAP" );
    }
    
    enode_list_push( &cc->e_stack, expr1 );
    enode_list_push( &cc->e_stack, expr2 );

    snail_emit( cc, ex, "\tc\n", SWAP );
}

static void snail_compile_over( SNAIL_COMPILER *cc, cexception_t *ex )
{
    ENODE *expr1 = cc->e_stack;
    ENODE *expr2 = expr1 ? enode_next( expr1 ) : NULL;
    TNODE *expr2_type = expr2 ? enode_type( expr2 ) : NULL;
    TYPETAB *generic_types = NULL;
    cexception_t inner;

    if( !expr1 || !expr2 ) {
	yyerrorf( "not enough values on the stack for OVER" );
    }

    generic_types = new_typetab( ex );

    cexception_guard( inner ) {
	if( tnode_lookup_operator( expr2_type, "over", 2 )) {
	    operator_description_t od;

	    snail_init_operator_description( &od, expr2_type, "over", 2 );
	    snail_check_operator_args( cc, &od, generic_types, ex );
	    snail_emit_operator_or_report_missing( cc, &od, NULL, "", ex );
	    snail_check_operator_retvals( cc, &od, 1, 1 );
	    snail_push_operator_retvals( cc, &od, NULL, generic_types,
					 ex );
	    snail_emit( cc, ex, "\n" );
	} else {
	    if( expr2_type ) {
		snail_push_type( cc, expr2_type, ex );
		share_tnode( expr2_type );
	    } else {
		yyerrorf( "when generating OVER, second expression from the "
			  "stack top has no type (?!)" );
	    }
	    snail_emit( cc, ex, "\tc\n", OVER );
	}
    }
    cexception_catch {
	delete_typetab( generic_types );
	cexception_reraise( inner, ex );
    }
    delete_typetab( generic_types );
}

static int snail_stack_top_has_operator( SNAIL_COMPILER *c,
					 char *operator_name,
					 int arity )
{
    ENODE *expr_enode = c ? c->e_stack : NULL;
    TNODE *expr_tnode = expr_enode ? enode_type( expr_enode ) : NULL;

    if( !expr_tnode ) {
	return 0;
    }
    
    if( !tnode_lookup_operator( expr_tnode, operator_name, arity )) {
	return 0;
    }

    return 1;
}

static int snail_nth_stack_value_has_operator( SNAIL_COMPILER *c,
					       int number_from_top,
					       char *operator_name,
					       int arity )
{
    ENODE *expr_enode = c ? c->e_stack : NULL;
    TNODE *expr_tnode; 

    while( number_from_top > 0 && expr_enode ) {
	expr_enode = enode_next( expr_enode );
	number_from_top --;
    }

    expr_tnode = expr_enode ? enode_type( expr_enode ) : NULL;

    if( !expr_tnode ) {
	return 0;
    }

    if( tnode_is_addressof( expr_tnode )) {
	expr_tnode = tnode_element_type( expr_tnode );
    }

    if( !tnode_lookup_operator( expr_tnode, operator_name, arity )) {
	return 0;
    }

    return 1;
}

static int snail_variable_has_operator( SNAIL_COMPILER *c,
                                        DNODE *var_dnode,
					char *operator_name,
					int arity )
{
    TNODE *var_tnode = NULL;
    DNODE *operator = NULL;

    if( ! var_dnode ) {
	return 0;
    }

    if( !( var_tnode = dnode_type( var_dnode ))) {
	return 0;
    }
    
    if( !( operator = tnode_lookup_operator( var_tnode, operator_name,
					     arity ))) {
	return 0;
    }

    return 1;
}

static void snail_compile_jnz_or_jz( SNAIL_COMPILER *c,
				     ssize_t offset,
				     char *operator_name,
				     void *pointer_opcode,
				     void *number_opcode,
				     cexception_t *ex )
{
    ENODE * volatile top_enode = c->e_stack;
    TNODE * volatile top_tnode = top_enode ? enode_type( top_enode ) : NULL;

    if( tnode_lookup_operator( top_tnode, operator_name, 1 )) {
	snail_check_and_compile_operator( c, top_tnode, operator_name,
					  /*arity:*/ 1,
					  /*fixup_values:*/ NULL, ex );
	snail_emit( c, ex, "e\n", &offset );
    } else {
	if( tnode_is_reference( top_tnode )) {
	    snail_emit( c, ex, "\tce\n", pointer_opcode, &offset );
	} else {
	    ssize_t zero = 0;
	    tnode_report_missing_operator( top_tnode, operator_name, 1 );
	    /* emit JMP instead of missing JNZ/JZ to avoid triggering
	       assertions later during backpatching: */
	    snail_emit( c, ex, "\tce\n", JMP, &zero );
	}
	compiler_drop_top_expression( c );
    }
}

static void snail_compile_jnz( SNAIL_COMPILER *c,
			       ssize_t offset,
			       cexception_t *ex )
{
    snail_compile_jnz_or_jz( c, offset, "jnz", PJNZ, JNZ, ex );
}

static void snail_compile_jz( SNAIL_COMPILER *c,
			      ssize_t offset,
			      cexception_t *ex )
{
    snail_compile_jnz_or_jz( c, offset, "jz", PJZ, JZ, ex );
}

static void snail_compile_loop( SNAIL_COMPILER *c,
				ssize_t offset,
				cexception_t *ex )
{
    ENODE * volatile limit_enode = c->e_stack;
    TNODE * volatile limit_tnode = limit_enode ?
	enode_type( limit_enode ) : NULL;

    ENODE * volatile counter_enode = limit_enode ?
	enode_next( limit_enode ) : NULL;
    TNODE * volatile counter_tnode = counter_enode ?
	enode_type( counter_enode ) : NULL;

    TNODE * volatile counter_base = counter_tnode ?
	tnode_element_type( counter_tnode ) : NULL;

    if( !counter_enode ) {
	yyerrorf( "too little values on the eval stack for LOOP operator" );
    }

    if( counter_base && limit_tnode &&
	!tnode_types_are_compatible( counter_base, limit_tnode, NULL, ex )) {
	yyerrorf( "incompatible types in counter and limit of 'for' "
		  "operator" );
    }

    if( limit_tnode ) {
	if( tnode_lookup_operator( limit_tnode, "loop", 2 )) {
	    snail_check_and_compile_operator( c, limit_tnode, "loop",
					      /*arity:*/ 2,
					      /*fixup_values:*/ NULL, ex );
	    snail_emit( c, ex, "e\n", &offset );
	} else {
	    tnode_report_missing_operator( limit_tnode, "loop", 2 );
	}
    }
}

static void snail_compile_alloc( SNAIL_COMPILER *cc,
				 TNODE *alloc_type,
				 cexception_t *ex )
{
    snail_push_type( cc, alloc_type, ex );
    if( !tnode_is_reference( alloc_type )) {
	yyerrorf( "only reference-implemented types can be "
		  "used in new operator" );
    }
    if( tnode_kind( alloc_type ) == TK_ARRAY ) {
	yyerrorf( "arrays should be allocated with array-new operator "
		  "(e.g. 'a = new int[20]')" );
    }

    if( snail_stack_top_has_operator( cc, "new", 1 )) {
	compiler_drop_top_expression( cc );
	snail_compile_operator( cc, alloc_type, "new", 1, ex );
    } else {
	ssize_t alloc_size = tnode_size( alloc_type );
	ssize_t alloc_nref = tnode_number_of_references( alloc_type );
	ssize_t vmt_offset = tnode_vmt_offset( alloc_type );

	if( vmt_offset == 0 ) {
	    snail_emit( cc, ex, "\tcee\n", ALLOC, &alloc_size, &alloc_nref );
	} else {
	    snail_emit( cc, ex, "\tceee\n", ALLOCVMT, &alloc_size, &alloc_nref,
			&vmt_offset );
	}
    }
}

static char *snail_make_typed_operator_name( TNODE *index_type1,
                                             TNODE *index_type2,
					     char *name_format,
					     cexception_t *ex )
{
    static char pad[20];
    static char *buff;
    ssize_t len;

    if( !index_type1 ) return NULL;

    if( index_type2 ) {
        len = snprintf( pad, sizeof(pad), name_format,
                        tnode_name( index_type1 ),
                        tnode_name( index_type2 ));
    } else {
        len = snprintf( pad, sizeof(pad), name_format,
                        tnode_name( index_type1 ));
    }

    if( len < sizeof( pad )) {
	return pad;
    } else {
	freex( buff );
	buff = NULL;
	buff = callocx( len+1, 1, ex );
        if( index_type2 ) {
            snprintf( buff, len+1, name_format,
                      tnode_name( index_type1 ),
                      tnode_name( index_type2 ));
        } else {
            snprintf( buff, len+1, name_format, tnode_name( index_type1 ));
        }
	return buff;
    }
}

static char* snail_indexing_operator_name( TNODE *index_type,
					   cexception_t *ex )
{
    return snail_make_typed_operator_name( index_type, NULL, "[%s]", ex );
}

static void snail_compile_composite_alloc_operator( SNAIL_COMPILER *cc,
						    TNODE *composite_type,
						    key_value_t *fixup_values,
						    cexception_t *ex )
{
    ENODE *volatile top_expr = cc->e_stack;
    TNODE *volatile top_type = top_expr ? enode_type( top_expr ) : NULL;
    const int arity = 1;
    char *operator_name;

    operator_name = snail_make_typed_operator_name( top_type, NULL, "new[%s]", ex );

    if( tnode_lookup_operator( composite_type, operator_name, arity )) {
	snail_check_and_compile_operator( cc, composite_type, operator_name,
					  arity, fixup_values, ex );
	/* Return value pushed by ..._compile_operator() function must
	   be dropped, since it only describes return value as having
	   type 'composite'. The caller of the current function will push
	   a correct return value 'composite of proper_element_type' */
	compiler_drop_top_expression( cc );
    } else {
	snail_check_and_remove_index_type( cc );
	tnode_report_missing_operator( composite_type, operator_name, arity );
    }
}

static void snail_compile_composite_alloc( SNAIL_COMPILER *cc,
					   TNODE *composite_type,
					   TNODE *element_type,
					   cexception_t *ex )
{
    TNODE *allocated_type = NULL;
    key_value_t *fixup_values = make_tnode_key_value_list( element_type );

    allocated_type = new_tnode_composite_synonim( composite_type, element_type,
						  ex );

    snail_compile_composite_alloc_operator( cc, allocated_type,
					    fixup_values, ex );

    snail_push_type( cc, allocated_type, ex );
    /* snail_push_composite_of_type( cc, composite_type, element_type, ex ); */
}

static void snail_compile_array_alloc_operator( SNAIL_COMPILER *cc,
						char *operator_name,
						key_value_t *fixup_values,
						cexception_t *ex )
{
    ENODE *volatile top_expr = cc->e_stack;
    TNODE *volatile top_type = top_expr ? enode_type( top_expr ) : NULL;
    const int arity = 1;

    if( snail_stack_top_has_operator( cc, operator_name, arity )) {
	snail_check_and_compile_operator( cc, top_type, operator_name,
					  arity, fixup_values, ex );
	/* Return value pushed by ..._compile_operator() function must
	   be dropped, since it only describes return value as having
	   type 'array'. The caller of the current function will push
	   a correct return value 'array of proper_element_type' */
	compiler_drop_top_expression( cc );
    } else {
	snail_check_and_remove_index_type( cc );
	tnode_report_missing_operator( top_type, operator_name, arity );
    }
}

static void snail_compile_array_alloc( SNAIL_COMPILER *cc,
				       TNODE *element_type,
				       cexception_t *ex )
{
    key_value_t *fixup_values = make_tnode_key_value_list( element_type );

    snail_compile_array_alloc_operator( cc, "new[]", fixup_values, ex );
    snail_push_array_of_type( cc, element_type, ex );
}

static void snail_compile_blob_alloc( SNAIL_COMPILER *cc,
				      cexception_t *ex )
{
    static key_value_t fixup_values[2] = {
	{ "element_nref", 0 },
	{ NULL },
    };

    snail_compile_array_alloc_operator( cc, "blob[]", fixup_values, ex );
    snail_push_type( cc, new_tnode_blob_snail( cc->typetab, ex ), ex );
}

static void snail_compile_mdalloc( SNAIL_COMPILER *cc,
				   TNODE *element_type,
				   int level,
				   cexception_t *ex )
{
    TNODE *array_tnode = new_tnode_array_snail( NULL, cc->typetab, ex );

    if( element_type ) {
	key_value_t *fixup_values =
	    make_mdalloc_key_value_list( element_type, level );

	snail_compile_array_alloc_operator( cc, "new[][]", fixup_values, ex );
	snail_append_expression_type( cc, array_tnode );
	snail_append_expression_type( cc, share_tnode( element_type ));
    } else {
	key_value_t fixup_vals[] = {
	    { "element_nref", 1 },
	    { "level", level },
	    { NULL }
	};

	if( level == 0 ) {
	    snail_compile_array_alloc_operator( cc, "new[]", fixup_vals, ex );
	    snail_push_type( cc, array_tnode, ex );
	} else {
	    snail_compile_array_alloc_operator( cc, "new[][]", fixup_vals, ex );
	    snail_append_expression_type( cc, array_tnode );
	}
    }
}

static void snail_begin_scope( SNAIL_COMPILER *c,
			       cexception_t *ex )
{
    assert( c );
    assert( c->vartab );

    push_int( &c->local_offset_stack, &c->local_offset_stack_size,
	      c->local_offset, ex );
    c->local_offset = starting_local_offset;
    vartab_begin_scope( c->vartab, ex );
    vartab_begin_scope( c->consts, ex );

    typetab_begin_scope( c->typetab, ex );
}

static void snail_end_scope( SNAIL_COMPILER *c, cexception_t *ex )
{
    assert( c );
    assert( c->vartab );

    c->local_offset = pop_int( &c->local_offset_stack,
			       &c->local_offset_stack_size, ex );
    vartab_end_scope( c->consts, ex );
    vartab_end_scope( c->vartab, ex );

    typetab_end_scope( c->typetab, ex );
}

static void snail_begin_subscope( SNAIL_COMPILER *c,
				  cexception_t *ex )
{
    assert( c );
    assert( c->vartab );

    vartab_begin_subscope( c->vartab, ex );
    vartab_begin_subscope( c->consts, ex );
    typetab_begin_subscope( c->typetab, ex );
}

static void snail_end_subscope( SNAIL_COMPILER *c, cexception_t *ex )
{
    assert( c );
    assert( c->vartab );

    vartab_end_subscope( c->consts, ex );
    vartab_end_subscope( c->vartab, ex );
    typetab_end_subscope( c->typetab, ex );
}

static void snail_push_guarding_arg( SNAIL_COMPILER *cc, cexception_t *ex )
{
    ENODE *arg = new_enode_guarding_arg( ex );
    enode_list_push( &cc->e_stack, arg );
}

static void snail_push_guarding_retval( SNAIL_COMPILER *cc, cexception_t *ex )
{
    ENODE *arg = new_enode_guarding_arg( ex );
    enode_set_flags( arg, EF_RETURN_VALUE );
    enode_list_push( &cc->e_stack, arg );
}

/*
  Function snail_push_varaddr_expr() pushes a fake expression with
  variable reference onto the stack. It is fake because no code is
  generated to push this "address". Instead, code emitter will emit
  'ST %variable' when encountered such expression.

  In principle, assignement to variables could be implemented as 'LDA
  %variable; compute_value; STI', but the scheme with fake variable
  references produces more efficient code 'compute_value; ST
  %variable'.
*/

static void snail_push_varaddr_expr( SNAIL_COMPILER *cc,
				     char *variable_name,
				     cexception_t *ex )
{
    DNODE *var_dnode = vartab_lookup( cc->vartab, variable_name );
    ENODE *arg = new_enode_varaddr_expr( var_dnode, ex );
    share_dnode( var_dnode );
    enode_list_push( &cc->e_stack, arg );
}

static type_kind_t snail_stack_top_type_kind( SNAIL_COMPILER *cc )
{
    ENODE *top_expr = cc->e_stack;
    TNODE *top_type = top_expr ? enode_type( cc->e_stack ) : NULL;

    if( top_type ) {
	return tnode_kind( top_type );
    } else {
	return TK_NONE;
    }
}

static void snail_make_stack_top_element_type( SNAIL_COMPILER *cc )
{
    if( cc->e_stack ) {
	enode_make_type_to_element_type( cc->e_stack );
    } else {
	yyerror( "not enough values on the evaluation stack for "
		 "taking base type?" );
    }
}

static DNODE* snail_make_stack_top_field_type( SNAIL_COMPILER *cc,
					       char *field_name )
{
    if( cc->e_stack ) {
	TNODE *struct_type = enode_type( cc->e_stack );
	DNODE *field = NULL;

	if( struct_type && tnode_kind( struct_type ) == TK_ADDRESSOF ) {
	    struct_type = tnode_element_type( struct_type );
	}

	field = struct_type ? 
	    tnode_lookup_field( struct_type, field_name ) : NULL;

	if( !field ) {
	    char *type_name = struct_type ? tnode_name( struct_type ) : NULL;
	    if( type_name ) {
		yyerrorf( "type '%s' has no field named '%s'",
			  type_name, field_name );
	    } else {
		yyerrorf( "this type has no field named '%s'", field_name );
	    }
	} else {
	    enode_replace_type( cc->e_stack, share_tnode( dnode_type( field )));
	}
	return field;
    } else {
	yyerror( "not enough values on the evaluation stack for "
		 "taking base type?" );
	return NULL;
    }
}

static void snail_make_stack_top_addressof( SNAIL_COMPILER *cc,
					    cexception_t *ex )
{
    if( cc->e_stack ) {
	enode_make_type_to_addressof( cc->e_stack, ex );
    } else {
	yyerror( "not enough values on the evaluation stack for "
		 "taking address?" );
    }    
}

static void snail_check_and_drop_function_args( SNAIL_COMPILER *cc,
						DNODE *function,
                                                TYPETAB *generic_types,
                                                cexception_t *ex )
{
    DNODE *function_args = dnode_function_args( function );
    DNODE *formal_arg = NULL;
    TNODE *formal_type, *actual_type;
    ssize_t n = 0;
    ssize_t nargs = dnode_list_length( function_args );

    foreach_dnode( formal_arg, function_args ) {
        if( !cc->e_stack || enode_has_flags( cc->e_stack, EF_GUARDING_ARG )) {
            if( cc->e_stack /* && !dnode_has_initialiser( formal_arg ) */) {
                yyerrorf( "too little arguments in call to function '%s'",
                          dnode_name( function ));
            }
            break;
        } else {
            ENODE *actual_arg = enode_list_pop( &cc->e_stack );
            formal_type = dnode_type( formal_arg );
            actual_type = enode_type( actual_arg );
            /* if( !tnode_types_are_identical( formal_type, actual_type )) { */
            if( !tnode_arguments_are_compatible( formal_type, actual_type,
                                                 generic_types, ex )) {
                yyerrorf( "incompatible types for function '%s' argument "
                          "nr. %d"/* " (%s)" */, dnode_name( function ),
                          nargs - n, dnode_name( formal_arg ));
            }
            if( !enode_is_readonly_compatible_for_init( actual_arg,
                                                        formal_arg )) {
                char *name = dnode_name( formal_arg );
                yyerrorf( "can not pass readonly value for r/w parameter "
                          "'%s'", name );
            }
            delete_enode( actual_arg );
            n++;
        }
    }

    if( cc->e_stack && !enode_has_flags( cc->e_stack, EF_GUARDING_ARG )) {
	char *fn_name = dnode_name( function );
	if( fn_name ) {
	    yyerrorf( "too many arguments in call to function '%s'",
		      dnode_name( function ));
	} else {
	    yyerrorf( "too many arguments in call to an anonymous function" );
	}
	while( cc->e_stack &&
	       !enode_has_flags( cc->e_stack, EF_GUARDING_ARG )) {
	    enode_list_drop( &cc->e_stack );
	}
    }
    enode_list_drop( &cc->e_stack );
}

static DNODE *snail_check_and_set_fn_proto( SNAIL_COMPILER *cc,
					    DNODE *fn_proto,
					    cexception_t *ex )
{
    DNODE *fn_dnode = NULL;
    TNODE *fn_tnode = NULL;
    char msg[100];

    if( (fn_dnode = vartab_lookup( cc->vartab, dnode_name( fn_proto )))
	    != NULL ) {
	fn_tnode = dnode_type( fn_dnode );
	if( !dnode_is_function_prototype( fn_dnode )) {
	    yyerrorf( "function '%s' is already declared in this scope",
		      dnode_name( fn_proto ));
	} else
	if( !tnode_function_prototypes_match_msg( fn_tnode,
					          dnode_type( fn_proto ),
					          msg, sizeof( msg ))) {
	    yyerrorf( "prototype of function %s() does not match "
		      "previous definition - %s", dnode_name( fn_proto ),
		      msg );
	}
	dnode_shallow_copy( fn_dnode, fn_proto, ex );
	delete_dnode( fn_proto );
	return fn_dnode;
    } else {
	snail_vartab_insert_named_vars( cc, fn_proto, ex );
	return fn_proto;
    }
}

static void snail_emit_argument_list( SNAIL_COMPILER *cc,
                                      DNODE *argument_list,
				      cexception_t *ex )
{
    DNODE *varnode;

    foreach_dnode( varnode, argument_list ) {
	TNODE *argtype = dnode_type( varnode );

	dnode_assign_offset( varnode, &cc->local_offset );
	vartab_insert_named( cc->vartab, varnode, ex );
	share_dnode( varnode );

	snail_emit_st( cc, argtype, dnode_name( varnode ),
		       dnode_offset( varnode ), dnode_scope( varnode ), ex );
    }
}

static void snail_emit_function_arguments( DNODE *function, SNAIL_COMPILER *cc,
					   cexception_t *ex )
{
    assert( function );
    snail_emit_argument_list( cc, dnode_function_args( function ), ex );
}

static void snail_emit_drop_returned_values( SNAIL_COMPILER *cc,
					     ssize_t drop_retvals,
					     cexception_t *ex  )
{
    if( drop_retvals > 1 ) {
	snail_compile_dropn( cc, drop_retvals, ex );
    } else if( drop_retvals == 1 ) {
	snail_compile_drop( cc, ex );
    }    
}

static ssize_t compiler_assemble_static_data( SNAIL_COMPILER *cc,
					      void *data,
					      ssize_t data_size,
					      cexception_t *ex )
{
    ssize_t new_size, old_size;

    assert( cc );

    old_size = cc->static_data_size;
    new_size = old_size + data_size;
    cc->static_data = reallocx( cc->static_data, new_size, ex );
    if( data ) {
	memcpy( cc->static_data + old_size, data, data_size );
    } else {
	memset( cc->static_data + old_size, 0, data_size );
    }
    cc->static_data_size = new_size;

    return old_size;
}

static void compiler_patch_static_data( SNAIL_COMPILER *cc,
					void *data,
					ssize_t data_size,
					ssize_t offset,
					cexception_t *ex )
{
    assert( cc );
    assert( offset > 0 );
    assert( offset + data_size <= cc->static_data_size );
    assert( data );

    memcpy( cc->static_data + offset, data, data_size );
}

#define ALIGN_NUMBER(N,lim)  ( (N) += ((lim) - ((ssize_t)(N)) % (lim)) % (lim) )

static void compiler_assemble_static_alloc_hdr( SNAIL_COMPILER *cc,
						ssize_t len,
						cexception_t *ex )
{
    ssize_t old_size, new_size;
    alloccell_t *hdr;

    new_size = old_size = cc->static_data_size;
    ALIGN_NUMBER( new_size, sizeof(void*) );

    compiler_assemble_static_data( cc, /* data */ NULL,
				   new_size - old_size + sizeof(alloccell_t),
				   ex );
    hdr = (alloccell_t*)(cc->static_data + new_size);
    hdr->magic = BC_MAGIC;
    hdr->flags |= AF_USED;
    hdr->length = len;
    hdr->size = len;
}

static ssize_t compiler_assemble_static_ssize_t( SNAIL_COMPILER *cc,
						 ssize_t size,
						 cexception_t *ex )
{
    return compiler_assemble_static_data( cc, &size, sizeof(size), ex );
}

static ssize_t compiler_assemble_static_string( SNAIL_COMPILER *cc,
						char *str,
						cexception_t *ex )
{
    compiler_assemble_static_alloc_hdr( cc, strlen(str) + 1, ex );
    return compiler_assemble_static_data( cc, str, strlen(str) + 1, ex );
}

static TNODE *snail_lookup_suffix_tnode( SNAIL_COMPILER *cc,
					 type_suffix_t suffix_type,
					 char *module_name,
					 char *suffix,
					 char *constant_kind_name )
{
    TNODE *const_type = NULL;
    DNODE *module  = NULL;

    if( module_name ) {
	module = vartab_lookup( cc->vartab, module_name );
	if( !module ) {
	    yyerrorf( "module '%s' is not available in the current scope",
		      module_name  );
	} else {
	    const_type =
		dnode_typetab_lookup_suffix( module, suffix ? suffix : "",
					     suffix_type );
	    if( !const_type ) {
		const_type =
		    dnode_typetab_lookup_type( module, suffix ? suffix : "" );
	    }
	}
    } else {
	const_type =
	    typetab_lookup_suffix( cc->typetab, suffix ? 
				   suffix : "", suffix_type );
	if( !const_type ) {
	    const_type = typetab_lookup( cc->typetab, suffix ? suffix : "" );
	    /* enumerator types should not be looked up: */
	}
    }

    if( !const_type ) {
	if( suffix ) {
	    yyerrorf( "type with suffix '%s' is not defined "
		      "in this scope for types of kind '%s'\n",
		      suffix, constant_kind_name );
	} else {
	    yyerrorf( "type with empty suffix is not defined "
		      "in this scope for types of kind '%s'\n",
		      constant_kind_name );
	}
    }

    return const_type;
}

static void snail_compile_enum_const_from_tnode( SNAIL_COMPILER *cc,
						 char *value_name,
						 TNODE *const_type,
						 cexception_t *ex )
{
    DNODE *const_dnode = const_type ?
	tnode_lookup_field( const_type, value_name ) : NULL;
    ssize_t string_offset = const_dnode ?
	dnode_offset( const_dnode ) : 0;

    if( !const_type ) {
	snail_push_error_type( cc, ex );
	return;
    }

    if( tnode_lookup_operator( const_type, "ldc", 0 ) != NULL ) {
	snail_compile_operator( cc, const_type, "ldc", 0, ex );
    } else {
	snail_push_type( cc, const_type, ex );
	share_tnode( const_type );
	tnode_report_missing_operator( const_type, "ldc", 0 );
    }

    if( !const_dnode ) {
	yyerrorf( "enumeration type '%s' does not have value '%s'",
		  tnode_name( const_type ), value_name );
    } else {
	if( !dnode_has_flags( const_dnode, DF_HAS_OFFSET )) {
	    ssize_t value = dnode_ssize_value( const_dnode );
	    char value_str[100];

	    snprintf( value_str, sizeof(value_str), "%d", value );
	    string_offset =
		compiler_assemble_static_string( cc, value_str, ex );
	    dnode_set_offset( const_dnode, string_offset );
	}
    }

    snail_emit( cc, ex, "e\n", &string_offset );
}

static TNODE* snail_lookup_tnode_silently( SNAIL_COMPILER *cc,
					   char *module_name,
					   char *identifier )
{
    if( !module_name ) {
	return typetab_lookup( cc->typetab, identifier );
    } else {
	DNODE *module = vartab_lookup( cc->vartab, module_name );
	if( !module ) {
	    yyerrorf( "module '%s' is not available in the current scope",
		      module_name  );
	    return NULL;
	} else {
	    return dnode_typetab_lookup_type( module, identifier );
	}
    }
}

static TNODE* snail_lookup_tnode( SNAIL_COMPILER *cc,
				  char *module_name,
				  char *identifier,
				  char *message )
{
    TNODE *typenode =
	snail_lookup_tnode_silently( cc, module_name, identifier );

    if( !typenode ) {
	if( !message ) message = "name";
	if( module_name ) {
	    yyerrorf( "%s '%s::%s' is not declared in the "
		      "current scope", message, module_name,
		      identifier );
	} else {
	    yyerrorf( "%s '%s' is not declared in the "
		      "current scope", message, identifier );
	}
    }
    return typenode;
}

static void snail_compile_enumeration_constant( SNAIL_COMPILER *cc,
						char *module_name,
						char *value_name,
						char *type_name,
						cexception_t *ex )
{
    TNODE *const_type =
	snail_lookup_tnode( cc, module_name, type_name, "enumeration type" );

    return snail_compile_enum_const_from_tnode( cc, value_name, const_type, ex );
}

static void snail_compile_typed_constant( SNAIL_COMPILER *cc,
					  TNODE *const_type,
					  char *value,
					  cexception_t *ex )
{
    if( const_type ) {
	ssize_t string_offset;

	if( tnode_kind( const_type ) == TK_ENUM ) {
	    if( strstr( value, " " )) {
		cexception_t inner;
		char *enum_value_name = strdupx( value, ex );
		char *val_end = strstr( enum_value_name, " " );

		if( val_end ) *val_end = '\0';
		cexception_guard( inner ) {
		    snail_compile_enum_const_from_tnode( cc, enum_value_name,
							 const_type, &inner );
		}
		cexception_catch {
		    freex( enum_value_name );
		    cexception_reraise( inner, ex );
		}
		freex( enum_value_name );
		return;
	    } else {
		yyerrorf( "enumerator type '%s' should not be given an "
			  "integer value\n",
			  tnode_name(const_type) ? tnode_name(const_type) : "" );
	    }
	}

	if( tnode_lookup_operator( const_type, "ldc", 0 ) != NULL ) {
	    snail_compile_operator( cc, const_type, "ldc", 0, ex );
	} else {
	    snail_push_type( cc, const_type, ex );
	    share_tnode( const_type );
	    tnode_report_missing_operator( const_type, "ldc", 0 );
	}
	string_offset = compiler_assemble_static_string( cc, value, ex );
	snail_emit( cc, ex, "e\n", &string_offset );
    }
}

static void snail_compile_constant( SNAIL_COMPILER *cc,
				    type_suffix_t suffix_type,
				    char *module_name,
				    char *suffix, char *constant_kind_name,
				    char *value,
				    cexception_t *ex )
{
    TNODE *const_type =
	snail_lookup_suffix_tnode( cc, suffix_type, module_name,
				   suffix, constant_kind_name );

    snail_compile_typed_constant( cc, const_type, value, ex );
}

static DNODE* snail_lookup_dnode_silently( SNAIL_COMPILER *cc,
					   char *module_name,
					   char *identifier )
{
    DNODE *module;

    if( !module_name ) {
	return vartab_lookup( cc->vartab, identifier );
    } else {
	module = vartab_lookup( cc->vartab, module_name );
	if( !module ) {
	    yyerrorf( "module '%s' is not available in the current scope",
		      module_name  );
	    return NULL;
	} else {
	    return dnode_vartab_lookup_var( module, identifier );
	}
    }
}

static DNODE* snail_lookup_dnode( SNAIL_COMPILER *cc,
				  char *module_name,
				  char *identifier,
				  char *message )
{
    DNODE *varnode =
	snail_lookup_dnode_silently( cc, module_name, identifier );

    if( !varnode ) {
	if( !message ) message = "name";
	if( module_name ) {
	    yyerrorf( "%s '%s::%s' is not declared in the "
		      "current scope", message, module_name,
		      identifier );
	} else {
	    yyerrorf( "%s '%s' is not declared in the "
		      "current scope", message, identifier );
	}
    }
    return varnode;
}

static DNODE* snail_lookup_constant( SNAIL_COMPILER *cc,
				     char *module_name,
				     char *identifier,
				     char *message )
{
    DNODE *module;
    DNODE *constnode;

    if( !module_name ) {
	constnode = vartab_lookup( cc->consts, identifier );
    } else {
	module = vartab_lookup( cc->vartab, module_name );
	if( !module ) {
	    yyerrorf( "module '%s' is not available in the current scope",
		      module_name  );
	    constnode = NULL;
	} else {
	    constnode = dnode_consttab_lookup_const( module, identifier );
	}
    }
    if( !constnode ) {
	if( !message ) message = "name";
	if( module_name ) {
	    yyerrorf( "%s '%s::%s' is not declared in the "
		      "current scope", message, module_name,
		      identifier );
	} else {
	    yyerrorf( "%s '%s' is not declared in the "
		      "current scope", message, identifier );
	}
    }
    return constnode;
}

static void snail_compile_ld( SNAIL_COMPILER *cc,
			      DNODE *varnode,
			      char *operator_name,
			      void *fallback_opcode,
			      TNODE* (*tnode_creator)
			          ( TNODE *base, cexception_t *xx ),
			      cexception_t *ex )
{
    cexception_t inner;
    DNODE *operator = NULL;
    const int arity = 0;
    ssize_t varnode_offset = 0;

    if( varnode ) {
	TNODE *var_type = dnode_type( varnode );
	TNODE * volatile expr_type = NULL;
	operator = tnode_lookup_operator( var_type, operator_name, arity );

	cexception_guard( inner ) {
	    if( tnode_creator ) {
		expr_type = tnode_creator( var_type, &inner );
	    } else {
		expr_type = var_type;
	    }
	    share_tnode( var_type );
	    snail_push_type( cc, expr_type, &inner );
	    if( dnode_has_flags( varnode, DF_IS_READONLY )) {
		enode_set_flags( cc->e_stack, EF_IS_READONLY );
	    }
	}
	cexception_catch {
	    delete_tnode( expr_type );
	    cexception_reraise( inner, ex );
	}

	if( operator ) {
	    snail_emit_function_call( cc, operator, NULL, "", ex );
	} else {
	    if( fallback_opcode == LDA ) {
		if( dnode_scope( varnode ) == snail_current_scope( cc )) {
		    if( tnode_is_reference( var_type )) {
			snail_emit( cc, ex, "\tc", PLDA );
		    } else {
			snail_emit( cc, ex, "\tc", LDA );
		    }
		} else {
		    if( dnode_scope( varnode ) == 0 ) {
			operator = tnode_lookup_operator( var_type, "ldga",
							  arity );
			if( operator ) {
			    snail_emit_function_call( cc, operator, NULL,
						      "", ex );
			} else {
			    if( tnode_is_reference( var_type )) {
				snail_emit( cc, ex, "\tc", PLDGA );
			    } else {
				snail_emit( cc, ex, "\tc", LDGA );
			    }
			}
		    } else {
			yyerrorf( "can only fetch variables either from the "
				  "current scope of from the scope 0" );
		    }
		}
	    } else if( fallback_opcode == LD ) {
		if( dnode_scope( varnode ) == snail_current_scope( cc )) {
		    if( tnode_is_reference( var_type )) {
			snail_emit( cc, ex, "\tc", PLD );
		    } else {
			snail_emit( cc, ex, "\tc", LD );
		    }
		} else {
		    if( dnode_scope( varnode ) == 0 ) {
			operator = tnode_lookup_operator( var_type, "ldg",
							  arity );
			if( operator ) {
			    snail_emit_function_call( cc, operator, NULL,
						      "", ex );
			} else {
			    if( tnode_is_reference( var_type )) {
				snail_emit( cc, ex, "\tc", PLDG );
			    } else {
				snail_emit( cc, ex, "\tc", LDG );
			    }
			}
		    } else {
			yyerrorf( "can only fetch variable addressess either "
				  "from the current scope of from "
				  "the scope 0" );
		    }
		}
	    } else {
		snail_emit( cc, ex, "\tc", fallback_opcode );
	    }
	}
	varnode_offset = dnode_offset( varnode );
	snail_emit( cc, ex, "eN\n", &varnode_offset, dnode_name( varnode ));
    } else {
	/* yyerrorf( "name '%s' not declared in the current scope",
	   identifier ); */
	snail_emit( cc, ex, "\tcNN\n", operator, "???", "???" );
	snail_push_error_type( cc, ex );
    }
}

static void snail_compile_load_variable_value( SNAIL_COMPILER *cc,
					       DNODE *varnode,
					       cexception_t *ex )
{
    snail_compile_ld( cc, varnode, "ld", LD, NULL, ex );
}

static void snail_compile_load_function_address( SNAIL_COMPILER *cc,
						 DNODE *varnode,
						 cexception_t *ex )
{
    snail_compile_ld( cc, varnode, "ldfn", LDFN, NULL, ex );
}

static void snail_compile_load_variable_address( SNAIL_COMPILER *cc,
						 DNODE *varnode,
						 cexception_t *ex )
{
    snail_compile_ld( cc, varnode, "lda", LDA, new_tnode_addressof, ex );
}

static void snail_fixup_function_calls( SNAIL_COMPILER *cc, DNODE *funct )
{
    char *name;
    int address;

    assert( funct );
    name = dnode_name( funct );
    address = dnode_offset( funct );

    thrcode_fixup_function_calls( cc->thrcode, name, address );
}

static void snail_compile_function_thrcode( SNAIL_COMPILER *cc )
{
    assert( cc );
    cc->thrcode = cc->function_thrcode;
}

static void snail_compile_main_thrcode( SNAIL_COMPILER *cc )
{
    assert( cc );
    cc->thrcode = cc->main_thrcode;
}

static void snail_merge_functions_and_main( SNAIL_COMPILER *cc,
					    cexception_t *ex  )
{
    assert( cc );
    thrcode_merge( cc->function_thrcode, cc->main_thrcode, ex );
    delete_thrcode( cc->main_thrcode );
    cc->main_thrcode = cc->function_thrcode;
    cc->function_thrcode = NULL;
    cc->thrcode = cc->main_thrcode;
	
}

static void snail_push_thrcode( SNAIL_COMPILER *sc,
			 cexception_t *ex )
{
    thrlist_push_data( &sc->thrstack, &sc->thrcode, delete_thrcode, NULL, ex );
    create_thrcode( &sc->thrcode, ex );
    elist_push_data( &sc->saved_estacks, &sc->e_stack, delete_enode, NULL, ex );
    sc->e_stack = NULL;
}

static void snail_swap_thrcodes( SNAIL_COMPILER *sc )
{
    THRCODE *code1 = thrlist_extract_data( sc->thrstack );
    ENODE *enode1 = elist_extract_data( sc->saved_estacks );

    thrlist_set_data( sc->thrstack, &sc->thrcode );
    assert( !sc->thrcode );
    sc->thrcode = code1;

    elist_set_data( sc->saved_estacks, &sc->e_stack );
    assert( !sc->e_stack );
    sc->e_stack = enode1;
}

static void snail_merge_top_thrcodes( SNAIL_COMPILER *sc, cexception_t *ex )
{
    thrcode_merge( sc->thrcode, thrlist_data( sc->thrstack ), ex );
    thrlist_drop( &sc->thrstack );
    sc->e_stack = 
	enode_append( elist_pop_data( &sc->saved_estacks ), sc->e_stack );
}

static void snail_get_inline_code( SNAIL_COMPILER *cc,
					    DNODE *function,
					    cexception_t *ex )
{
    ssize_t code_start = snail_pop_address( cc, ex );
    ssize_t code_end = thrcode_length( cc->thrcode );
    ssize_t code_length = code_end - code_start;
    int is_inline = dnode_has_flags( function, DF_INLINE );

    if( code_length > 0 && is_inline ) {
	thrcode_t *opcodes = NULL;
	opcodes = thrcode_instructions( cc->thrcode );
	dnode_set_code( function, opcodes + code_start, code_length, ex );
	dnode_adjust_code_fixups( function, code_start );
    }
}

static int snail_count_return_values( DNODE *funct )
{
    TNODE *function_type = funct ? dnode_type( funct ) : NULL;
    DNODE *retvals = function_type ? tnode_retvals( function_type ) : NULL;

    return dnode_list_length( retvals );
}

static void snail_compile_address_of_indexed_element( SNAIL_COMPILER *cc,
						      cexception_t *ex )
{
    cexception_t inner;
    ENODE * volatile index_expr = NULL;
    ENODE * volatile array_expr = NULL;
    TNODE *index_type = NULL;
    TNODE *array_type = NULL;
    TNODE *element_type = NULL;
    char *idx_name = NULL;
    operator_description_t od;
    const int idx_arity = 2;
    TYPETAB *volatile generic_types = NULL;

    index_expr = cc->e_stack;

    index_type = index_expr ? enode_type( index_expr ) : NULL;
    array_expr = cc->e_stack ? enode_next( cc->e_stack ) : NULL;

    cexception_guard( inner ) {
        generic_types = new_typetab( &inner );
	idx_name = snail_indexing_operator_name( index_type, &inner );

	if( array_expr ) {
	    array_type = enode_type( array_expr );
	    if( array_type && tnode_kind( array_type ) == TK_ADDRESSOF ) {
		array_type = tnode_element_type( array_type );
	    }
	    element_type = array_type ? tnode_element_type( array_type ) : NULL;
	}

	if( !array_type ) {
	    yyerrorf( "not enough values on the stack for indexing operator" );
	}

	if( tnode_lookup_operator( array_type, idx_name, idx_arity )) {
	    snail_init_operator_description( &od, array_type, idx_name,
					     idx_arity );
	} else {
	    snail_init_operator_description( &od, index_type, "[]", idx_arity );
	}

	if( od.operator ) {
	    snail_check_operator_args( cc, &od, generic_types,
                                       &inner );
	}

	index_expr = enode_list_pop( &cc->e_stack );

	if( od.operator ) {
	    TNODE *return_type = NULL;
	    key_value_t *fixup_values = NULL;

	    array_expr = cc->e_stack;

	    fixup_values = make_tnode_key_value_list( element_type );

	    snail_emit_operator_or_report_missing( cc, &od, fixup_values,
						   "", &inner );

	    snail_check_operator_retvals( cc, &od, 1, 1 );
	    return_type = od.retvals ? dnode_type( od.retvals ) : NULL;

	    if( return_type ) {
		if( tnode_kind( return_type ) == TK_ADDRESSOF &&
		    tnode_element_type( return_type ) == NULL ) {
		    if( !element_type ) {
			yyerrorf( "can not index array with unknown element "
				  "type" );
		    }
		    if( snail_stack_top_type_kind( cc ) ==  TK_ADDRESSOF ) {
			snail_make_stack_top_element_type( cc );
		    }
		    snail_make_stack_top_element_type( cc );
		    snail_make_stack_top_addressof( cc, &inner );
		} else {
		    enode_list_drop( &cc->e_stack );
		    snail_push_type( cc, return_type, &inner );
		    share_tnode( return_type );
		}
	    }
	    snail_emit( cc, &inner, "\n" );
	} else {
	    snail_make_stack_top_element_type( cc );
	    snail_make_stack_top_addressof( cc, &inner );
	    tnode_report_missing_operator( index_type, "[]", idx_arity );
	}
    }
    cexception_catch {
	delete_enode( index_expr );
        delete_typetab( generic_types );
	cexception_reraise( inner, ex );
    }
    delete_enode( index_expr );
    delete_typetab( generic_types );
}

static void snail_compile_subarray( SNAIL_COMPILER *cc,
                                    cexception_t *ex )
{
    cexception_t inner;
    ENODE * volatile index_expr1 = NULL;
    ENODE * volatile index_expr2 = NULL;
    ENODE * volatile array_expr = NULL;
    TNODE *index_type1 = NULL;
    TNODE *index_type2 = NULL;
    TNODE *array_type = NULL;
    TNODE *element_type = NULL;
    char *idx_name = NULL;
    operator_description_t od;
    const int idx_arity = 3;
    TYPETAB *volatile generic_types = NULL;

    index_expr1 = cc->e_stack;
    index_expr2 = index_expr1 ? enode_next( index_expr1 ) : NULL;
    array_expr = index_expr2 ? enode_next( index_expr2 ) : NULL;
    
    index_type1 = index_expr1 ? enode_type( index_expr1 ) : NULL;
    index_type2 = index_expr2 ? enode_type( index_expr2 ) : NULL;

    if( !index_expr1 || !index_expr2 ) {
        /* The compiler tried to emit two expressions (the ones in the
           [expr1..expr2] brackets), and told us that we should have
           them, but they are not on the emlated expression stack --
           something must have been very wrong during the compilation
           of the range... S.G. */
        cexception_raise
            ( ex, SNAIL_UNRECOVERABLE_ERROR,
              "subarray index range expressions were not generated properly" );
    }
    /* From now on, index_expr1 and index_expr2 are not NULL */

    cexception_guard( inner ) {
        generic_types = new_typetab( &inner );
        idx_name = snail_make_typed_operator_name( index_type1, index_type2,
                                                   "[%s..%s]", ex );

	if( array_expr ) {
	    array_type = enode_type( array_expr );
	    if( array_type && tnode_kind( array_type ) == TK_ADDRESSOF ) {
		array_type = tnode_element_type( array_type );
	    }
	    element_type = array_type ? tnode_element_type( array_type ) : NULL;
	}

	if( !array_type ) {
	    yyerrorf( "not enough values on the stack "
                      "for a subarray/substring operator" );
	}

	if( tnode_lookup_operator( array_type, idx_name, idx_arity )) {
	    snail_init_operator_description( &od, array_type, idx_name,
					     idx_arity );
	} else if( tnode_lookup_operator( index_type1, idx_name, idx_arity )) {
	    snail_init_operator_description( &od, index_type1, "[..]",
                                             idx_arity );
	} else {
            snail_init_operator_description( &od, index_type2, "[..]",
                                             idx_arity );
        }

	if( od.operator ) {
	    snail_check_operator_args( cc, &od, generic_types,
                                       &inner );
	}

	index_expr1 = enode_list_pop( &cc->e_stack );
	index_expr2 = enode_list_pop( &cc->e_stack );

	if( od.operator ) {
	    TNODE *return_type = NULL;
	    key_value_t *fixup_values = NULL;

	    array_expr = cc->e_stack;

	    fixup_values = make_tnode_key_value_list( element_type );

	    snail_emit_operator_or_report_missing( cc, &od, fixup_values,
						   "", &inner );

	    snail_check_operator_retvals( cc, &od, 1, 1 );
	    return_type = od.retvals ? dnode_type( od.retvals ) : NULL;

	    if( return_type ) {
		assert( tnode_kind( return_type ) != TK_ADDRESSOF );
                if( tnode_kind( return_type ) == TK_ARRAY &&
                    tnode_element_type( return_type )) {
                    enode_list_drop( &cc->e_stack );
                    snail_push_type( cc, return_type, &inner );
                    share_tnode( return_type );
                }
	    }
	    snail_emit( cc, &inner, "\n" );
	} else {
	    tnode_report_missing_operator( index_type1, "[..]", idx_arity );
	}
    }
    cexception_catch {
	delete_enode( index_expr1 );
	delete_enode( index_expr2 );
        delete_typetab( generic_types );
	cexception_reraise( inner, ex );
    }
    delete_enode( index_expr1 );
    delete_enode( index_expr2 );
    delete_typetab( generic_types );
}

static void snail_compile_indexing( SNAIL_COMPILER *cc,
				    int array_is_reference,
				    int expr_count,
				    cexception_t *ex )
{
    if( expr_count == 1 ) {
	snail_compile_address_of_indexed_element( cc, ex );
    } else if( expr_count == 0 ) {
	assert( array_is_reference );
        snail_emit( cc, ex, "\tc\n", CLONE );
    } else if( expr_count == -1 ) {
	assert( 0 );
    } else if( expr_count == 2 ) {
	assert( array_is_reference );
        snail_compile_subarray( cc, ex );
    } else {
	assert( 0 );
    }
}

static void snail_compile_type_declaration( SNAIL_COMPILER *cc,
					    TNODE *type_descr,
					    cexception_t *ex )
{
    cexception_t inner;
    ANODE * volatile suffix = NULL;
    TNODE *tnode = NULL;
    char * volatile type_name = NULL;

    if( !type_descr ) return;

    type_name = strdupx( tnode_name( cc->current_type ), ex );

    cexception_guard( inner ) {
	assert( type_descr );
	if( tnode_name( type_descr ) == NULL ) {
	    tnode = tnode_set_name( type_descr, type_name, &inner );
	} else if( type_descr != cc->current_type ) {
	    tnode = tnode_set_name( new_tnode_synonim( type_descr, &inner ),
				    type_name, &inner );
	    suffix = new_anode_string_attribute( "suffix", tnode_name( tnode ),
						 &inner );
	    tnode_set_attribute( tnode, suffix, &inner );
	} else {
	    tnode = type_descr;
	}
	snail_typetab_insert( cc, tnode, &inner );
	tnode = typetab_lookup( cc->typetab, type_name );
	tnode_reset_flags( tnode, TF_IS_FORWARD );
	snail_insert_tnode_into_suffix_list( cc, tnode, &inner );
	cc->current_type = NULL;
	freex( type_name );
    }
    cexception_catch {
	freex( type_name );
	delete_anode( suffix );
	cexception_reraise( inner, ex );
    }
    delete_anode( suffix );
}

static ssize_t compiler_native_type_size( const char *name )
{
    if( strcmp( name, "int" ) == 0 ) {
	return sizeof( int );
    } else
    if( strcmp( name, "long" ) == 0 ) {
	return sizeof( long );
    } else
    if( strcmp( name, "short" ) == 0 ) {
	return sizeof( short );
    } else
    if( strcmp( name, "char" ) == 0 ) {
	return sizeof( char );
    } else
    if( strcmp( name, "float" ) == 0 ) {
	return sizeof( float );
    } else
    if( strcmp( name, "double" ) == 0 ) {
	return sizeof( double );
    } else
    if( strcmp( name, "ldouble" ) == 0 ) {
	return sizeof( ldouble );
    } else
    if( strcmp( name, "long double" ) == 0 ) {
	return sizeof( long double );
    } else
    if( strcmp( name, "llong" ) == 0 ) {
	return sizeof( llong );
    } else
    if( strcmp( name, "ullong" ) == 0 ) {
	return sizeof( ullong );
    } else
    if( strcmp( name, "long long" ) == 0 ) {
	return sizeof( long long );
    } else
    if( strcmp( name, "size_t" ) == 0 ) {
	return sizeof( size_t );
    } else
    if( strcmp( name, "ssize_t" ) == 0 ) {
	return sizeof( ssize_t );
    } else
    if( strcmp( name, "void*" ) == 0 ) {
	return sizeof( void* );
    } else
    if( strcmp( name, "char*" ) == 0 ) {
	return sizeof( char* );
    } else
    if( strcmp( name, "bytecode_file_hdr_t" ) == 0 ) {
	return sizeof( bytecode_file_hdr_t );
    } else {
	yyerrorf( "native type '%s' is not known to the compiler", name );
	return -1;
    } 
}

static ssize_t compiler_native_type_nreferences( const char *name )
{
    if( strcmp( name, "bytecode_file_hdr_t" ) == 0 ) {
	return INTERPRET_FILE_PTRS;
    } else {
#if 1
	return 0;
#else
	yyerrorf( "number of references in type '%s' "
		  "is not known to the compiler", name );
	return -1;
#endif
    } 
}

static int compiler_check_and_emit_program_arguments( SNAIL_COMPILER *cc,
						      DNODE *args,
						      cexception_t *ex )
{
    DNODE *arg;
    int n = 1;
    int retval = 1;

    args = dnode_list_invert( args );
    foreach_dnode( arg, args ) {
	TNODE *arg_type = dnode_type( arg );
	switch( n ) {
	case 1:
	case 3:
	    if( !tnode_is_array_of_string( arg_type )) {
		yyerrorf( "argument nr. %d of the program must be "
			  "'array of string'", n );
		retval = 0;
	    }
	    if( n == 1 ) {
		snail_emit( cc, ex, "\tcT\n", ALLOCARGV, "(* argv *)" );
	    } else {
		snail_emit( cc, ex, "\tcT\n", ALLOCENV, "(* env *)" );
	    }
	    break;
	case 2:
	    if( !tnode_is_array_of_file( arg_type )) {
		yyerrorf( "argument nr. %d of the program must be "
			  "'array of file'", n );
		retval = 0;
	    }
	    snail_emit( cc, ex, "\tcT\n", ALLOCSTDIO, "(* stdio *)" );
	    break;
	}
	n++;
    }
    args = dnode_list_invert( args );
    if( --n > 3 ) {
	yyerrorf( "too many arguments for the program "
		  "(found %d, must be <= 3)", n );
	retval = 0;
    }
    return retval;
}

static void compiler_compile_program_args( SNAIL_COMPILER *cc,
					   char *program_name,
					   DNODE *argument_list,
					   TNODE *return_type,
					   cexception_t *ex )
{
    if( compiler_check_and_emit_program_arguments( cc, argument_list, ex )) {
	snail_emit_argument_list( cc, argument_list, ex );
    }
}

static void snail_emit_catch_comparison( SNAIL_COMPILER *cc,
					 char *module_name,
					 char *exception_name,
					 cexception_t *ex )
{
    DNODE *exception = vartab_lookup( cc->vartab, exception_name );
    ssize_t zero = 0;
    ssize_t exception_val;
    ssize_t try_var_offset = cc->try_variable_stack ?
	cc->try_variable_stack[cc->try_block_level-1] : 0;

    if( !exception ) {
	yyerrorf( "exception '%s' is not defined at the current point",
		  exception_name );
    }

    if( module_name ) {
	snail_emit( cc, ex, "\n\tce\n", PLD, &try_var_offset );
	snail_emit( cc, ex, "\n\tc\n", EXCEPTIONMODULE );
	snail_emit( cc, ex, "\tce\n", SLDC, &module_name );
	snail_emit( cc, ex, "\tc\n", EQBOOL );
	snail_push_relative_fixup( cc, ex );
	snail_emit( cc, ex, "\tce\n", BJNZ, &zero );
    }

    snail_emit( cc, ex, "\n\tce\n", PLD, &try_var_offset );
    snail_emit( cc, ex, "\n\tc\n", EXCEPTIONID );

    exception_val = exception ? dnode_ssize_value( exception ) : 0;
    snail_emit( cc, ex, "\tce\n", LDC, &exception_val );
    snail_emit( cc, ex, "\tc\n", EQBOOL );

    if( module_name ) {
	snail_fixup_here( cc );
    }
}

static void snail_finish_catch_comparisons( SNAIL_COMPILER *cc,
					    int nfixups,
					    cexception_t *ex )
{
    int i;
    ssize_t zero = 0;

    snail_push_relative_fixup( cc, ex );
    snail_emit( cc, ex, "\tce\n", BJZ, &zero );
    for( i = 0; i < nfixups; i ++ ) {
	/* fixup all JNZs emitted in the 'exception_identifier_list'
	   rule: */
	snail_swap_fixups( cc );
	snail_fixup_here( cc );
    }
}

static void snail_finish_catch_block( SNAIL_COMPILER *cc, cexception_t *ex )
{
    ssize_t zero = 0;

    cc->catch_jumpover_nr ++;
    snail_push_relative_fixup( cc, ex );
    snail_emit( cc, ex, "\tce\n", JMP, &zero );
    snail_swap_fixups( cc );
    snail_fixup_here( cc );
}

static void compiler_check_enum_attributes( TNODE *tnode )
{
    TNODE *base = tnode ? tnode_base_type( tnode ) : NULL;
    char *name = tnode ? tnode_name( tnode ) : NULL;

    if( base ) {
	if( tnode_size( base ) != tnode_size( tnode )) {
	    if( name ) {
		yyerrorf( "specified size of the enum '%s' does not match size"
			  "of its parent type", name );
	    } else {
		yyerrorf( "specified size of the enum does not match size"
			  "of its parent type" );
	    }
	}
    }
}

static void snail_convert_function_argument( SNAIL_COMPILER *cc,
					     cexception_t *ex )
{
    TNODE *arg_type = cc->current_arg ? dnode_type( cc->current_arg ) : NULL;
    TNODE *exp_type = cc->e_stack ? enode_type( cc->e_stack ) : NULL;

    if( arg_type && exp_type ) {
	if( tnode_kind( arg_type ) != TK_PLACEHOLDER &&
	    !tnode_types_are_identical( arg_type, exp_type, NULL, ex )) {
	    char *arg_type_name = tnode_name( arg_type );
	    if( arg_type_name ) {
		snail_compile_type_conversion( cc, arg_type_name, ex );
	    }
	}
    }
    cc->current_arg = cc->current_arg ? dnode_prev( cc->current_arg ) : NULL;
}

static void snail_compile_typed_const_value( SNAIL_COMPILER *cc,
					     TNODE *const_type,
					     const_value_t *v,
					     cexception_t *ex )
{
    cexception_t inner;
    value_t vtype = v->value_type;
    TNODE * volatile tnode = NULL;

    cexception_guard( inner ) {
	switch( vtype ) {
	    case VT_INT:
		const_value_to_string( v, &inner );
		snail_compile_typed_constant( cc, const_type,
					      const_value_string( v ),
					      &inner );
		break;
	    case VT_FLOAT:
		const_value_to_string( v, &inner );
		snail_compile_typed_constant( cc, const_type,
					      const_value_string( v ),
					      &inner );
		break;
	    case VT_STRING:
		const_value_to_string( v, &inner );
		snail_compile_typed_constant( cc, const_type,
					      const_value_string( v ),
					      &inner );
		break;
	    case VT_ENUM:
		const_value_to_string( v, &inner );
		snail_compile_typed_constant( cc, const_type,
					      const_value_string( v ),
					      &inner );
		break;
	    case VT_NULL: {
		    tnode = new_tnode_nullref( &inner );
		    snail_push_type( cc, tnode, &inner );
		    tnode = NULL;
		    snail_emit( cc, &inner, "\tc\n", PLDZ );
	        }
		break;
	    default:
		assert(0);
	}
	const_value_free( v );
    }
    cexception_catch {
	const_value_free( v );
	delete_tnode( tnode );
	cexception_reraise( inner, ex );
    }
}

static void snail_compile_multitype_const_value( SNAIL_COMPILER *cc,
                                                 const_value_t *v,
                                                 char *module_name,
                                                 char *suffix_name,
                                                 cexception_t *ex )
{
    TNODE *const_type = NULL;
    value_t vtype = v->value_type;

    switch( vtype ) {
    case VT_INT:
	const_type = snail_lookup_suffix_tnode( cc, TS_INTEGER_SUFFIX,
						module_name, suffix_name,
						"integer" );
	break;
    case VT_FLOAT:
	const_type = snail_lookup_suffix_tnode( cc, TS_FLOAT_SUFFIX,
						module_name, suffix_name,
						"float" );
	break;
    case VT_STRING:
	const_type = snail_lookup_suffix_tnode( cc, TS_STRING_SUFFIX,
						module_name, suffix_name,
						"string" );
	break;
    case VT_ENUM: {
	cexception_t inner;
	char *volatile value_name = NULL;
	char *type_name;
	char *value_name_terminator;

	assert( v->value.s );

	type_name = strstr( v->value.s, " " );
	assert( type_name );
	type_name ++;

	value_name = strdupx( v->value.s, ex );
	value_name_terminator = strstr( value_name, " " );
	assert( value_name_terminator );
	*value_name_terminator = '\0';

	cexception_guard( inner ) {
	    snail_compile_enumeration_constant( cc, module_name,
						value_name, type_name,
						&inner );
	}
	cexception_catch {
	    freex( value_name );
	    cexception_reraise( inner, ex );
	}
	freex( value_name );
	return;
	break;
    }
    case VT_NULL:
	const_type = NULL;
	break;
    default:
	assert( 0 );
	break;
    }

    snail_compile_typed_const_value( cc, const_type, v, ex );
}

static void snail_emit_default_arguments( SNAIL_COMPILER *cc,
					  char *arg_name,
					  cexception_t *ex )
{
    DNODE *arg;

    arg = cc->current_arg;
    while( arg && ( !arg_name || strcmp( arg_name, dnode_name( arg )) != 0 )) {
	if( dnode_has_initialiser( arg )) {
	    const_value_t const_value = make_zero_const_value();

	    const_value_copy( &const_value, dnode_value( arg ), ex );
	    snail_compile_typed_const_value( cc, dnode_type( arg ),
					     &const_value, ex );
	} else {
	    if( arg ) {
		if( arg_name ) {
		    yyerrorf( "parameter '%s' has no default value, "
			      "please supply its value before '%s'",
			      dnode_name( arg ), arg_name );
		} else {
		    yyerrorf( "parameter '%s' has no default value, "
			      "please supply its value",
			      dnode_name( arg ) );
		}
	    }
	}
	arg = dnode_prev( arg );
    }
    if( arg == NULL && arg_name != NULL ) {
	yyerrorf( "function '%s' has no argument '%s' to emit",
		  dnode_name( cc->current_call ), arg_name );
    }
    cc->current_arg = arg;
}

static void compiler_check_forward_functions( SNAIL_COMPILER *c )
{
    FIXUP *f;
    FIXUP *forward_calls = thrcode_forward_functions( c->thrcode );

    foreach_fixup( f, forward_calls ) {
	char *name = fixup_name( f );
	yyerrorf( "function %s() declared forward but never defined", name );
    }
}

static void compiler_check_raise_expression( SNAIL_COMPILER *c,
					     char *exception_name,
					     cexception_t *ex )
{
    DNODE *exception = vartab_lookup( c->vartab, exception_name );
    TNODE *top_type = NULL;

    if( !exception ) {
	yyerrorf( "Exception '%s' is not defined at this point",
		  exception_name );
    }

    if( !c->e_stack ) {
	yyerrorf( "Not enough values on the stack for raising exception?" );
    }
    if( !(top_type = enode_type( c->e_stack ))) {
	yyerrorf( "Value on the top of the stack is untyped when "
		  "raising exception?" );
    }
    snail_check_and_compile_operator( c, top_type, "exceptionset", 1,
                                      NULL, ex );
}

static struct {
    char *exception_name;
    sl_exception_t exception_nr;
} default_exceptions[] = {
    { "TestException",            SL_EXCEPTION_TEST_EXCEPTION     },
    { "OutOfMemoryException",     SL_EXCEPTION_OUT_OF_MEMORY      },
    { "FileOpenError",            SL_EXCEPTION_FILE_OPEN_ERROR    },
    { "FileReadError",            SL_EXCEPTION_FILE_READ_ERROR    },
    { "FileWriteError",           SL_EXCEPTION_FILE_WRITE_ERROR   },
    { "NullPointerError",         SL_EXCEPTION_NULL_ERROR         },
    { "SystemException",          SL_EXCEPTION_SYSTEM_ERROR,      },
    { "ExternalLibraryException", SL_EXCEPTION_EXTERNAL_LIB_ERROR },
    { "MissingIncludePathException", SL_EXCEPTION_MISSING_INCLUDE_PATH },
    { "HashFullException",        SL_EXCEPTION_HASH_FULL} ,
    { "BoundError",               SL_EXCEPTION_BOUND_ERROR },
    { "BlobOverflowException",    SL_EXCEPTION_BLOB_OVERFLOW },
    { "BadBlobDescriptor",        SL_EXCEPTION_BLOB_BAD_DESCR },
    { "ArrayOverflowException",   SL_EXCEPTION_ARRAY_OVERFLOW },

    { NULL, SL_EXCEPTION_NULL }
};

static void snail_insert_default_exceptions( SNAIL_COMPILER *c,
					     cexception_t *ex )
{
    int i;

    for( i = 0; default_exceptions[i].exception_name != NULL; i ++ ) {

	snail_compile_exception( c, default_exceptions[i].exception_name,
				 default_exceptions[i].exception_nr, ex );

	c->latest_exception_nr = default_exceptions[i].exception_nr;

    }
}

static void snail_compile_file_input_operator( SNAIL_COMPILER *cc,
					       cexception_t *ex )
{
    ENODE *top_expr = cc->e_stack;
    TNODE *top_type = top_expr ? enode_type( top_expr ) : NULL;

    if( top_type && tnode_is_addressof( top_type )) {
	top_type = tnode_element_type( top_type );
    }

    snail_swap_thrcodes( cc );

    if( top_type ) {
	ENODE *file_expr = cc->e_stack;
	TNODE *file_type = file_expr ? enode_type( file_expr ) : NULL;

	if( file_type ) {
	    snail_push_type( cc, share_tnode( file_type ), ex );
	} else {
	    snail_push_type( cc, NULL, ex );
	}
	snail_check_and_compile_operator( cc, top_type, ">>",
					  /*arity:*/ 1,
					  /*fixup_values:*/ NULL, ex );
	snail_emit( cc, ex, "\n" );
    }

    snail_merge_top_thrcodes( cc, ex );
    snail_compile_swap( cc, ex );
    snail_compile_sti( cc, ex );
}

static void snail_compile_variable_initialisations( SNAIL_COMPILER *cc,
						    DNODE *lst,
						    cexception_t *ex )
{
    DNODE *var;

    foreach_dnode( var, lst ) {
	if( dnode_has_flags( var, DF_HAS_INITIALISER )) {
	    snail_compile_initialise_variable( cc, var, ex );
	}
    }
}

static void snail_compile_zero_out_stackcells( SNAIL_COMPILER *cc,
					       DNODE *variables,
					       cexception_t *ex )
{
    DNODE *var;
    ssize_t nvars = 0;
    ssize_t offset = 0;
    ssize_t min_offset = 0;
    int must_zero = 0;

    foreach_dnode( var, variables ) {
	if( !dnode_has_flags( var, DF_HAS_INITIALISER )) {
	    must_zero = 1;
	}
	nvars ++;
	offset = dnode_offset( var );
	if( min_offset == 0 || offset < min_offset ) {
	    min_offset = offset;
	}
    }
    if( must_zero ) {
	snail_emit( cc, ex, "\tcee\n", ZEROSTACK, &min_offset, &nvars );
    }
}

static void compiler_begin_package( SNAIL_COMPILER *c,
				    DNODE *package,
				    cexception_t *ex )
{
    compiler_push_symbol_tables( c, ex );
    vartab_insert_named( c->compiled_packages, package, ex );
    vartab_insert_named( c->vartab, share_dnode( package ), ex );
    dlist_push_dnode( &c->current_package_stack, &c->current_package, ex );
    c->current_package = package;
}

static void compiler_end_package( SNAIL_COMPILER *c, cexception_t *ex )
{
    compiler_pop_symbol_tables( c );
    c->current_package = dlist_pop_data( &c->current_package_stack );
}

static char *compiler_find_package( SNAIL_COMPILER *c,
				    const char *package_name,
				    cexception_t *ex )
{
    static char buffer[300];
    ssize_t len;

    len = snprintf( buffer, sizeof(buffer), "%s.slib", package_name );

    assert( len < sizeof(buffer) );

    return buffer;
}

static int compiler_can_compile_use_statement( SNAIL_COMPILER *cc,
					       char *statement )
{
    assert( cc );
    if( cc->current_function ) {
	yyerrorf( "'%s' statement should not be used within subroutines",
		  statement );
	return 0;
    }
    if( cc->loops ) {
	yyerrorf( "'%s' statement should not be used within loops",
		  statement );
	return 0;
    }
    return 1;
}

static void compiler_import_package( SNAIL_COMPILER *c,
				     char *package_name,
				     cexception_t *ex )
{
    DNODE *package = vartab_lookup( c->compiled_packages, package_name );

    if( !compiler_can_compile_use_statement( c, "import" )) {
	return;
    }

    if( package != NULL ) {
	vartab_insert_named( c->vartab, share_dnode( package ), ex );
	/* printf( "found compiled package '%s'\n", package_name ); */
    } else {
	char *pkg_path = compiler_find_package( c, package_name, ex );
	compiler_open_include_file( c, pkg_path, ex );
    }
}

static void compiler_use_package( SNAIL_COMPILER *c,
				  char *package_name,
				  cexception_t *ex )
{
    DNODE *package = vartab_lookup( c->compiled_packages, package_name );

    if( !compiler_can_compile_use_statement( c, "use" )) {
	return;
    }

    if( package != NULL ) {
	vartab_insert_named( c->vartab, share_dnode( package ), ex );
	/* printf( "found compiled package '%s'\n", package_name ); */
	compiler_use_exported_package_names( c, package, ex );
    } else {
	char *pkg_path = compiler_find_package( c, package_name, ex );
	compiler_open_include_file( c, pkg_path, ex );
	if( c->use_package_name ) {
	    freex( c->use_package_name );
	}
	c->use_package_name = strdupx( package_name, ex );
    }
}

static void compiler_debug()
{
    printf( "Debug statement reached in line %d\n",
	    snail_flex_current_line_number() );
}

static void snail_compile_multiple_assignment( SNAIL_COMPILER *cc,
					       ssize_t nvars,
					       ssize_t nvars_left,
					       ssize_t nvalues,
					       cexception_t *ex )
{
    ssize_t i;

    if( nvars > nvalues ) {
	yyerrorf( "there are more variables than values to asign" );
    }

    if( nvars < nvalues ) {
	snail_compile_dropn( cc, nvalues - nvars, ex );
    }

    for( i = 0; i < nvars_left; i++ ) {
	snail_merge_top_thrcodes( cc, ex );
	if( enode_is_varaddr( cc->e_stack )) {
	    DNODE *var = enode_variable( cc->e_stack );

	    share_dnode( var );
	    compiler_drop_top_expression( cc );
	    snail_compile_variable_assignment( cc, var, ex );
	    delete_dnode( var );
	} else {
	    snail_compile_swap( cc, ex );
	    snail_compile_sti( cc, ex );
	}
    }
    snail_swap_thrcodes( cc );
    snail_merge_top_thrcodes( cc, ex );
}

static void snail_compile_array_expression( SNAIL_COMPILER* cc,
					    ssize_t nexpr,
					    cexception_t *ex )
{
    ssize_t i;
    int is_readonly = 0;

    if( nexpr > 0 ) {
	ENODE *top = enode_list_pop( &cc->e_stack );
	TNODE *top_type = enode_type( top );
	ssize_t nrefs = tnode_is_reference( top_type ) ? 1 : 0;

	if( enode_has_flags( top, EF_IS_READONLY ) &&
	    tnode_is_reference( top_type ) &&
	    !tnode_is_immutable( top_type )) {
	    is_readonly = 1;
	}
	for( i = 1; i < nexpr; i++ ) {
	    ENODE *curr = enode_list_pop( &cc->e_stack );
	    TNODE *curr_type = enode_type( curr );
	    if( !tnode_types_are_identical( top_type, curr_type, NULL, ex )) {
		yyerrorf( "incompatible types of array components" );
	    }
	    if( enode_has_flags( curr, EF_IS_READONLY ) &&
		tnode_is_reference( curr_type ) &&
		!tnode_is_immutable( curr_type )) {
		is_readonly = 1;
	    }
	    delete_enode( curr );
	}
	if( tnode_is_reference( top_type )) {
	    snail_emit( cc, ex, "\tce\n", PMKARRAY, &nexpr );
	} else {
	    snail_emit( cc, ex, "\tcee\n", MKARRAY, &nrefs, &nexpr );
	}
	snail_push_array_of_type( cc, share_tnode( top_type ), ex );
	if( is_readonly ) {
	    enode_set_flags( cc->e_stack, EF_IS_READONLY );
	}
	delete_enode( top );
    }
}

static void snail_push_loop( SNAIL_COMPILER *cc, char *loop_label,
			     cexception_t *ex )
{
    char label[200];
    cc->loops =
	new_dnode_loop( loop_label, cc->loops, ex );

    if( !loop_label ) {
	snprintf( label, sizeof(label), "@%p", cc->loops );
	dnode_set_name( cc->loops, label, ex );
    }
}

static void snail_pop_loop( SNAIL_COMPILER *cc )
{
    DNODE *top_loop = cc->loops;

    assert( top_loop );
    cc->loops = dnode_next( top_loop );
    dnode_disconnect( top_loop );

    delete_dnode( top_loop );
}

static void snail_fixup_op_continue( SNAIL_COMPILER *cc, cexception_t *ex )
{
    DNODE *loop = cc->loops;

    assert( loop );

    thrcode_fixup_op_continue( cc->thrcode, dnode_name( loop ),
			       thrcode_length( cc->thrcode ));
}

static void snail_fixup_op_break( SNAIL_COMPILER *cc, cexception_t *ex )
{
    DNODE *loop = cc->loops;

    assert( loop );

    thrcode_fixup_op_break( cc->thrcode, dnode_name( loop ),
			    thrcode_length( cc->thrcode ));
}

static char *snail_get_loop_name( SNAIL_COMPILER *cc, char *label )
{
    if( !label ) {
	DNODE *latest_loop = cc->loops;
	char *name = latest_loop ? dnode_name( latest_loop ) : NULL;
	return name;
    } else {
#if 0
	DNODE *loop;
	int found = 0;
	foreach_dnode( loop, cc->loops ) {
	    if( strcmp( dnode_name(loop), label ) == 0 ) {
		found = 1;
		break;
	    }
	}
	if( !found ) {
	    yyerrorf( "label '%s' is not defined in the current scope",
		      label );
	}
#endif
	return label;
    }
}

static ssize_t check_loop_types( SNAIL_COMPILER *cc, char *label )
{
    DNODE *loop;
    int found = 0;
    ssize_t count = 0;

    foreach_dnode( loop, cc->loops ) {
	if( dnode_has_flags( loop, DF_LOOP_HAS_VAL )) {
	    count ++;
	}
	if( strcmp( dnode_name(loop), label ) == 0 ) {
	    found = 1;
	    break;
	}
    }
    if( !found ) {
	yyerrorf( "label '%s' is not defined in the current scope", label );
    }
    return count;
}

static int snail_check_break_and_cont_statements( SNAIL_COMPILER *cc )
{
    assert( cc );
    if( !cc->loops ) {
	yyerrorf( "'break' and 'continue' statements can be used "
		  "only in loops" );
	return 0;
    }
    return 1;
}

static void snail_drop_loop_counters( SNAIL_COMPILER *cc, char *name,
				      int delta,
				      cexception_t *ex )
{
    ssize_t loop_values = check_loop_types( cc, name );

    if( loop_values > 0 ) {
	ssize_t nvalues = ( loop_values - delta ) * 2;
	snail_emit( cc, ex, "\tce\n", PDROPN, &nvalues );
    }
}

static void snail_compile_break( SNAIL_COMPILER *cc, char *label,
				 cexception_t *ex )
{
    ssize_t zero = 0;

    if( snail_check_break_and_cont_statements( cc )) {
	char *name = snail_get_loop_name( cc, label );

	snail_drop_loop_counters( cc, name, 0, ex );

	if( name ) {
	    thrcode_push_op_break_fixup( cc->thrcode, name, ex );
	}
	snail_emit( cc, ex, "\tce\n", JMP, &zero );
    }
}

static void snail_compile_continue( SNAIL_COMPILER *cc, char *label,
				    cexception_t *ex )
{
    ssize_t zero = 0;

    if( snail_check_break_and_cont_statements( cc )) {
	char *name = snail_get_loop_name( cc, label );

	snail_drop_loop_counters( cc, name, 1, ex );

	if( name ) {
	    thrcode_push_op_continue_fixup( cc->thrcode, name, ex );
	}
	snail_emit( cc, ex, "\tce\n", JMP, &zero );
    }
}

static void snail_set_function_arguments_readonly( TNODE *funct_type )
{
    DNODE *arg;
    DNODE *arg_list = funct_type ? tnode_args( funct_type ) : NULL;

    foreach_dnode( arg, arg_list ) {
	TNODE *arg_type = dnode_type( arg );
	if( tnode_is_reference( arg_type ) &&
	    !tnode_is_immutable( arg_type )) {
	    dnode_set_flags( arg, DF_IS_READONLY );
	}
    }
}

static void snail_check_default_value_compatibility( DNODE *arg,
						     const_value_t *val )
{
    TNODE *arg_type = dnode_type( arg );
    type_kind_t arg_kind = arg_type ? tnode_kind( arg_type ) : TK_NONE;
    value_t val_kind = const_value_type( val );

    if( arg_kind == TK_INTEGER || arg_kind == TK_BOOL ) {
	if( val_kind != VT_INT ) {
	    yyerrorf( "default value is not compatible with the "
		      "function argument '%s' of type '%s'",
		      dnode_name( arg ), tnode_name( arg_type ));
	}
    } else
    if( arg_kind == TK_REAL ) {
	if( val_kind != VT_FLOAT && val_kind != VT_INT ) {
	    yyerrorf( "default value is not compatible with the "
		      "function argument '%s' of type '%s'",
		      dnode_name( arg ), tnode_name( arg_type ));
	}
    } else
    if( arg_kind == TK_STRING ) {
	if( val_kind != VT_STRING && val_kind != VT_NULL ) {
	    yyerrorf( "default value is not compatible with the "
		      "function argument '%s' of type '%s'",
		      dnode_name( arg ), tnode_name( arg_type ));
	}
    } else
    if( arg_kind == TK_ENUM ) {
	if( val_kind != VT_ENUM ) {
	    yyerrorf( "default value is not compatible with the "
		      "function argument '%s' of type '%s'",
		      dnode_name( arg ), tnode_name( arg_type ));
	}
    } else
    if( tnode_is_reference( arg_type )) {
	if( val_kind != VT_NULL ) {
	    yyerrorf( "default value is not compatible with the "
		      "function argument '%s' of type '%s'",
		      dnode_name( arg ), tnode_name( arg_type ));
	}
    } else {
	yyerrorf( "default value is not compatible with the "
		  "function argument '%s'", dnode_name( arg ));
    }
}

static const_value_t compiler_make_compiler_attribute( char *attribute_name,
						       cexception_t *ex )
{
    if( strcmp( attribute_name, "stackcellsize" ) == 0 ) {
	return make_const_value( ex, VT_INT, sizeof(stackcell_t) );
    } else {
	yyerrorf( "unknown compiler attribute '%s' requested",
		  attribute_name );
	return make_zero_const_value();
    }
}

static 
const_value_t compiler_get_tnode_compile_time_attribute( TNODE *tnode,
							 char *attribute_name,
							 cexception_t *ex )
{
    if( strcmp( attribute_name, "size" ) == 0 ) {
	return make_const_value( ex, VT_INT, tnode_size( tnode ));
    } else
    if( strcmp( attribute_name, "nref" ) == 0 ) {
	return make_const_value( ex, VT_INT,
				 tnode_number_of_references( tnode ));
    } else {
	yyerrorf( "unknown compile-time attribute '%s' requested",
		  attribute_name );
	return make_zero_const_value();
    }
}

static
const_value_t compiler_get_dnode_compile_time_attribute( DNODE *dnode,
							 char *attribute_name,
							 cexception_t *ex )
{
    if( !dnode ) {
	return make_zero_const_value();
    }

    if( strcmp( attribute_name, "offset" ) == 0 ) {
	return make_const_value( ex, VT_INT, dnode_offset( dnode ));
    } else {
	TNODE *tnode = dnode_type( dnode );
	return compiler_get_tnode_compile_time_attribute( tnode,
							  attribute_name, ex );
    }
}

static const_value_t compiler_make_compile_time_value( SNAIL_COMPILER *cc,
						       char *package_name,
						       char *identifier,
						       char *attribute_name,
						       cexception_t *ex )
{
    DNODE *variable = NULL;
    TNODE *tnode = NULL;

    variable = snail_lookup_dnode_silently( cc, package_name, identifier );

    if( !variable ) {
	tnode = snail_lookup_tnode_silently( cc, package_name, identifier );
	if( tnode ) {
	    return compiler_get_tnode_compile_time_attribute( tnode,
							      attribute_name,
							      ex );
	} else {
	    if( !tnode ) {
		yyerrorf( "neither type nor variable '%s' can be found to "
			  "provide attribute '%s'",
			  identifier, attribute_name );
	    }
	    return make_zero_const_value();
	}
    } else {
	return compiler_get_dnode_compile_time_attribute( variable,
							  attribute_name, ex );
    }
}

static DNODE* compiler_lookup_type_field( SNAIL_COMPILER *cc,
					  char *package_name,
					  char *identifier,
					  char *field_identifier )
{
    DNODE *variable = NULL;
    TNODE *tnode = NULL;
    DNODE *field;

    variable = snail_lookup_dnode_silently( cc, package_name, identifier );

    if( !variable ) {
	tnode = snail_lookup_tnode_silently( cc, package_name, identifier );
	if( !tnode ) {
	    yyerrorf( "neither type nor variable '%s' can be found when "
		      "searching for field '%s'", identifier, field_identifier );
	}
    } else {
	tnode = dnode_type( variable );
	if( !tnode ) {
	    yyerrorf( "type of variable '%s' is not defined",
		      identifier );	    
	}
    }
    if( tnode ) {
	field = tnode_lookup_field( tnode, field_identifier );
	if( !field ) {
	    yyerrorf( "%s '%s' does not have member '%s'",
		      variable ? "variable" : "type",
		      identifier, field_identifier );
	    return NULL;
	} else {
	    return field;
	}
    } else {
	return NULL;
    }
}

static char *basename( char *filename )
{
    char *start = filename;

    if( !start ) return NULL;
    while( *start ) start++;
    while( start >= filename && *start != '/' ) start --;
    return start+1;
}

static char *extension( char *filename )
{
    if( !filename ) return NULL;
    while( *filename && *filename != '.' ) filename ++;
    return filename;
}

typedef void DL_HANDLE;

static void compiler_load_library( SNAIL_COMPILER *snail_cc,
				   char *library_filename,
				   char *opcode_array_name,
				   cexception_t *ex )
{
    cexception_t inner;
    char *library_name_start = basename( library_filename );
    char *library_name_end = extension( library_name_start );
    ssize_t library_name_length = library_name_end - library_name_start;
    char *library_name = callocx( 1, library_name_length + 1, ex );

    char *library_path =
        compiler_find_include_file( snail_cc, library_filename, ex );

    strncpy( library_name, library_name_start, library_name_length );

    cexception_guard( inner ) {
	const char *opcodes_symbol = "OPCODES";
	DL_HANDLE *lib = dlopen( library_path, RTLD_LAZY );

	if( !lib ) {
	    char *errmsg = dlerror();
	    errmsg = rindex( errmsg, ':' );
	    if( errmsg ) errmsg ++;
	    if( errmsg && *errmsg == ' ' ) errmsg ++;
	    if( errmsg && *errmsg ) {
		yyerrorf( "could not open shared library '%s' - %c%s",
			  library_filename, tolower(*errmsg), errmsg+1 );
	    } else {
		yyerrorf( "could not open shared library '%s'",
                          library_filename );
	    }
	} else {
	    char **opcodes = dlsym( lib, opcodes_symbol );
	    int (*init)( istate_t* );
	    int (*trace_on)( int );
	    if( !opcodes ) {
		yyerrorf( "shared library '%s' does not contain symbol %s",
			  library_filename, opcodes_symbol );
	    } else {
		tcode_add_table( library_name, lib, opcodes, &inner );
	    }
	    if( (init = dlsym( lib, "init" )) != NULL ) {
		(*init)( &istate );
	    }
	    if( (trace_on = dlsym( lib, "trace_on" )) != NULL ) {
		(*trace_on)( trace );
	    }
	}
    }
    cexception_catch {
	freex( library_name );
	cexception_reraise( inner, ex );
    }
    freex( library_name );
}

static void snail_check_and_push_function_name( SNAIL_COMPILER *cc,
						char *module_name,
						char *function_name,
						cexception_t *ex )
{
    TNODE *fn_tnode = NULL;

    dlist_push_dnode( &cc->current_call_stack,
		      &cc->current_call, ex );

    dlist_push_dnode( &cc->current_arg_stack,
		      &cc->current_arg, ex );

    cc->current_call = 
	share_dnode( snail_lookup_dnode( cc, module_name, function_name,
					 "function" ));

    fn_tnode = cc->current_call ?
	dnode_type( cc->current_call ) : NULL;

    if( fn_tnode &&
	tnode_kind( fn_tnode ) != TK_FUNCTION_REF &&
	tnode_kind( fn_tnode ) != TK_FUNCTION &&
	tnode_kind( fn_tnode ) != TK_OPERATOR ) {
	char *fn_name = cc->current_call ?
	    dnode_name( cc->current_call ) : NULL;
	if( fn_name ) {
	    yyerrorf( "call to non-function '%s'", fn_name );
	} else {
	    yyerrorf( "call to non-function" );
	}
    }
}

static ssize_t snail_compile_multivalue_function_call( SNAIL_COMPILER *cc,
						       cexception_t *ex )
{
    cexception_t inner;
    DNODE *funct = cc->current_call;
    TNODE *fn_type = funct ? dnode_type( funct ) : NULL;
    ssize_t rval_nr = 0;
    /* Generic types represented by "placeholder" tnodes pointing to
       the actual instances of these types in a particular function
       call: */
    TYPETAB *volatile generic_types = NULL; 

    cexception_guard( inner ) {
	generic_types = new_typetab( &inner );
        if( funct && fn_type ) {
            snail_emit_default_arguments( cc, NULL, &inner );
            snail_check_and_drop_function_args( cc, funct, generic_types,
                                                &inner );
            snail_emit_function_call( cc, funct, NULL, "\n", &inner );
            if( tnode_kind( fn_type ) == TK_FUNCTION_REF ) {
                compiler_drop_top_expression( cc );
            }
            snail_push_function_retvals( cc, funct, generic_types, &inner );
            rval_nr = snail_count_return_values( funct );
        } else {
            while( cc->e_stack &&
                   !enode_has_flags( cc->e_stack, EF_GUARDING_ARG )) {
                compiler_drop_top_expression( cc );
            }
            assert( cc->e_stack );
            assert( enode_has_flags( cc->e_stack, EF_GUARDING_ARG ));
            compiler_drop_top_expression( cc );
            /* Push NULL value to maintain stack value balance and
               avoid segfaults or asserts in the downstream code: */
            snail_push_error_type( cc, &inner );
            rval_nr = 1;
        }
	delete_typetab( generic_types );
    }
    cexception_catch {
	delete_typetab( generic_types );
        cexception_reraise( inner, ex );
    }

    delete_dnode( cc->current_call );

    cc->current_call =
	dlist_pop_data( &cc->current_call_stack );
    cc->current_arg =
	dlist_pop_data( &cc->current_arg_stack );

    return rval_nr;
}

static void compiler_compile_virtual_method_table( SNAIL_COMPILER *cc,
						   TNODE *class_descr,
						   cexception_t *ex )
{
    ssize_t vmt_address, vmt_start;
    ssize_t max_vmt_entry;
    DNODE *volatile method;
    TNODE *volatile base;

    assert( class_descr );

    max_vmt_entry = tnode_max_vmt_offset( class_descr );

    compiler_assemble_static_alloc_hdr( cc, sizeof(ssize_t), ex );

    vmt_address = compiler_assemble_static_ssize_t( cc, 1, ex );

    tnode_set_vmt_offset( class_descr, vmt_address );

    compiler_assemble_static_ssize_t( cc, vmt_address + 2*sizeof(ssize_t), ex );

    vmt_start =
	compiler_assemble_static_ssize_t( cc, max_vmt_entry, ex );

#if 0
	    printf( ">>> class '%s', interface table starts at %d, vmt[1] starts at %d\n",
		    tnode_name( class_descr ),
		    vmt_address, vmt_start );
#endif

    compiler_assemble_static_data( cc, NULL,
				   max_vmt_entry*sizeof(ssize_t), ex );

    foreach_tnode_base_class( base, class_descr ) {
	DNODE *methods = tnode_methods( base );
	foreach_dnode( method, methods ) {
	    ssize_t method_index = dnode_offset( method );
	    ssize_t method_address = dnode_ssize_value( method );
	    ssize_t compiled_addr;
#if 0
	    printf( ">>> class '%s', method '%s', offset %d, address %d\n",
		    tnode_name( base ), dnode_name( method ),
		    dnode_offset( method ), dnode_ssize_value( method ));
#endif
	    compiled_addr = 
		*(ssize_t*)
		(&cc->static_data[vmt_start + method_index * sizeof(ssize_t)]);
	    if( method_index != 0 && method_address != 0 && compiled_addr == 0 ) {
		compiler_patch_static_data( cc, /* void *data: */ &method_address,
					    /* ssize_t data_size: */
					    sizeof(method_address),
					    /* ssize_t offset: */
					    vmt_start +
					    method_index * sizeof(ssize_t),
					    ex );
	    }
	}
    }
}

static SNAIL_COMPILER * volatile snail_cc;

static cexception_t *px; /* parser exception */

%}

%union {
  long i;
  char *s;
  ANODE *anode;        /* type attribute description */
  TNODE *tnode;
  DNODE *dnode;
  ENODE *enode;
  int token;           /* token value returned by lexer */
  int op;              /* type of the assign operator; for simple assignement
			  operator, contains '='; for operators like '+=' and
			  '*=' contains '+' and '*', correspondingly; for
			  operators like '**=' contains token for '**', in this
			  case __STAR_STAR */
  const_value_t c;     /* value of a constant being computed; strings
		          are allocated. */
}

%token _ADDRESSOF
%token _BLOB
%token _ARRAY
%token _BREAK
%token _BYTECODE
%token _CATCH
%token _CLASS
%token _CONST
%token _CONTINUE
%token _DEBUG
%token _DO
%token _ELSE
%token _ENDDO
%token _ENDIF
%token _ENUM
%token _EXCEPTION
%token _FOR
%token _FORWARD
%token _FUNCTION
%token _IF
%token _IMPORT
%token _INCLUDE
%token _INLINE
%token _LIKE
%token _LOAD
%token _METHOD
%token _MODULE
%token _NATIVE
%token _NEW
%token _NULL
%token _OF
%token _OPERATOR
%token _PACK
%token _PACKAGE
%token _PROCEDURE
%token _PROGRAM
%token _RAISE
%token _READONLY
%token _RERAISE
%token _RETURN
%token _SHL
%token _SHR
%token _SIZEOF
%token _STRUCT
%token _THEN
%token _TO
%token _TRY
%token _TYPE
%token _UNPACK
%token _USE
%token _VAR
%token _WHILE

%token __ASSIGN /* := */
%token __INC    /* ++ */
%token __DEC    /* -- */
%token __DOT_DOT /* .. */
%token __COLON_COLON /* :: */
%token __THREE_DOTS /* ... */
%token __ARROW  /* -> */
%token __THICK_ARROW /* => */
%token __STAR_STAR /* ** */
%token __LEFT_TO_RIGHT /* >> */
%token __RIGHT_TO_LEFT /* << */
%token __DOUBLE_PERCENT /* %% */

%token <s> __ARITHM_ASSIGN  /* +=, -=, *=, etc. */

%token <s> __IDENTIFIER
%token <s> __INTEGER_CONST
%token <s> __REAL_CONST
%token <s> __STRING_CONST

%type <dnode> argument
%type <dnode> argument_list
%type <dnode> argument_identifier_list
%type <c>     constant_expression
%type <i>     constant_integer_expression
%type <tnode> dimension_list
%type <dnode> enum_member
%type <tnode> enum_member_list
%type <i>     expression_list
%type <dnode> field_designator
%type <dnode> function_header
%type <dnode> method_header
%type <dnode> method_definition
%type <i>     multivalue_function_call
%type <i>     multivalue_expression
%type <i>     multivalue_expression_list
%type <s>     import_statement
%type <s>     include_statement
%type <i>     index_expression
%type <i>     lvalue_list
%type <i>     md_array_allocator
%type <dnode> operator_definition
%type <dnode> operator_header
%type <i>     function_attributes
%type <dnode> function_definition
%type <i>     function_or_procedure_keyword
%type <i>     function_or_procedure_type_keyword
%type <tnode> opt_base_type
%type <i>     opt_function_attributes
%type <s>     opt_label
%type <i>     opt_readonly
%type <dnode> opt_retval_description_list
%type <dnode> package_name
%type <dnode> retval_description_list
%type <i>     size_constant
%type <tnode> struct_description
%type <tnode> struct_or_class_declaration_body
%type <tnode> struct_or_class_description_body
%type <tnode> class_description
%type <dnode> struct_field
%type <tnode> struct_declaration_field_list
%type <tnode> struct_description_field_list
%type <dnode> struct_operator
%type <tnode> struct_operator_list
%type <dnode> struct_var_declaration
%type <tnode> finish_fields
%type <tnode> compact_type_description
%type <s>     type_declaration_name
%type <tnode> type_identifier
%type <tnode> var_type_description
%type <tnode> undelimited_or_structure_description
%type <tnode> undelimited_type_description
%type <tnode> delimited_type_description
%type <anode> type_attribute
%type <s>     use_statement
%type <dnode> variable_access_identifier
%type <dnode> variable_access_for_indexing
%type <dnode> variable_identifier
%type <dnode> variable_identifier_list
%type <i>     variable_declaration_keyword
%type <dnode> variable_declarator_list
%type <dnode> uninitialised_var_declarator_list
%type <dnode> variable_declarator
%type <dnode> for_variable_declaration
%type <i>     exception_identifier_list

%left __ARROW
%right __ASSIGN '='

%left '?' ':'

%left _OR
%left _AND

%left  '<' '>' __EQ __NE __LE  __GE

%left  '_'
%left __DOUBLE_PERCENT
%left  '+' '-' '|' '^'
%left  '*' '/' '%' '&' _SHR _SHL __LEFT_TO_RIGHT  __RIGHT_TO_LEFT
%left  __STAR_STAR

%left __COLON_COLON /* :: */

%left '@'

/* %left _AS */

%right __UNARY

%%

Program
  :   {
        ssize_t zero = 0;
        assert( snail_cc );
        snail_insert_default_exceptions( snail_cc, px );
        snail_compile_function_thrcode( snail_cc );
	snail_push_absolute_fixup( snail_cc, px );
	snail_emit( snail_cc, px, "\tce\n", ENTER, &zero );
	snail_push_relative_fixup( snail_cc, px );
	snail_emit( snail_cc, px, "\tce\n", JMP, &zero );
        snail_compile_main_thrcode( snail_cc );
      }
    statement_list
      {
	snail_compile_function_thrcode( snail_cc );
	snail_fixup_here( snail_cc );
	snail_fixup( snail_cc, -snail_cc->local_offset );
	snail_merge_functions_and_main( snail_cc, px );
	compiler_check_forward_functions( snail_cc );
	snail_emit( snail_cc, px, "\tc\n", NULL );
      }
  ;

statement_list
  : delimited_statement
  | statement_list ';' delimited_statement
  | undelimited_statement_list delimited_statement
  ;

undelimited_statement_list
  : undelimited_statement
  | statement_list ';' undelimited_statement
  | undelimited_statement_list undelimited_statement
  ;

statement
  : delimited_statement
  | undelimited_statement
  ;

delimited_statement
  : multivalue_function_call
    { snail_emit_drop_returned_values( snail_cc, $1, px ); }
  | assignment_statement
  | variable_declaration
  | constant_declaration
  | exception_declaration
  | function_prototype
  | delimited_type_declaration
  | return_statement
  | raise_statement
  | incdec_statement
  | io_statement
  | program_statement
  | delimited_control_statement
  | package_statement
  | break_or_continue_statement
  | pack_statement

  | /* empty statement */
  ;

/* pack a,    20,     4,    8;
   //-- blob, offset, size, value
*/
pack_statement
: _PACK expression ',' expression ',' expression ',' expression
{
    TNODE *type_to_pack = enode_type( snail_cc->e_stack );

    if( type_to_pack ) {
	if( tnode_kind( type_to_pack ) == TK_ARRAY ) {
	    TNODE *element_type = tnode_element_type( type_to_pack );
	    if( element_type && tnode_kind( element_type ) == TK_ARRAY ) {
		key_value_t *fixup_values;
		int level = 1;
		do {
		    level ++;
		    element_type = tnode_element_type( element_type );
		} while( element_type && tnode_kind( element_type ) == TK_ARRAY );
		fixup_values =
		    make_mdalloc_key_value_list( element_type, level );
		snail_check_and_compile_operator( snail_cc, element_type,
						  "packmdarray", 4 /* arity */,
						  fixup_values, px );
	    } else {
		snail_check_and_compile_operator( snail_cc, element_type,
						  "packarray", 4 /* arity */,
						  NULL /* fixup_values */, px );
	    }
	} else {
	    snail_check_and_compile_operator( snail_cc, type_to_pack,
					      "pack", 4 /* arity */,
					  NULL /* fixup_values */, px );
	}
	snail_emit( snail_cc, px, "\n" );
    } else {
	yyerrorf( "top expression has no type???" );
    }
}
;

break_or_continue_statement
  : _BREAK
    { snail_compile_break( snail_cc, NULL, px ); }
  | _BREAK __IDENTIFIER
    { snail_compile_break( snail_cc, $2, px ); }
  | _CONTINUE
    { snail_compile_continue( snail_cc, NULL, px ); }
  | _CONTINUE __IDENTIFIER
    { snail_compile_continue( snail_cc, $2, px ); }
  ;

undelimited_simple_statement
  : include_statement
       { compiler_open_include_file( snail_cc, $1, px ); }
  | import_statement
       { compiler_import_package( snail_cc, $1, px ); }
  | use_statement
       { compiler_use_package( snail_cc, $1, px ); }
  | load_library_statement
  | bytecode_statement
  | function_definition
  | operator_definition
    {
	TNODE *operator = dnode_type( $1 );
	DNODE *arg1 = tnode_args( operator );
	TNODE *arg1_type = dnode_type( arg1 );

	/* should probably check whether operator is declared in the
	   same module as the type. */
	tnode_insert_single_operator( arg1_type, $1 );
    }
  | compound_statement
  | undelimited_type_declaration
  | debug_statement
  ;

undelimited_statement
  : undelimited_simple_statement
  | control_statement
  ;

non_control_statement
  : delimited_statement
  | undelimited_simple_statement
  ;

debug_statement
  : _DEBUG
    {
	compiler_debug();
    }
  ;

do_prefix
  : _DO
    {
      snail_push_current_address( snail_cc, px );
      snail_push_thrcode( snail_cc, px );
    }
  ;

non_control_statement_list
  : non_control_statement
  | non_control_statement_list ';' non_control_statement
  ;

delimited_control_statement
  : do_prefix non_control_statement_list
      {
	snail_swap_thrcodes( snail_cc );
      }
    if_condition
      {
	snail_merge_top_thrcodes( snail_cc, px );
        snail_fixup_here( snail_cc );
	snail_pop_offset( snail_cc, px );
      }

  | do_prefix non_control_statement_list _WHILE 
      {
	snail_swap_thrcodes( snail_cc );
	snail_merge_top_thrcodes( snail_cc, px );
      }
    expression
      {
	snail_compile_jnz( snail_cc, snail_pop_offset( snail_cc, px ), px );
      }

  ;

raise_statement
  : _RAISE
    {
	ssize_t zero = 0;
	ssize_t minus_one = -1;
	snail_emit( snail_cc, px, "\tce\n", LDC, &minus_one );
	snail_emit( snail_cc, px, "\tc\n", PLDZ );
	snail_emit( snail_cc, px, "\tcee\n", RAISE, &zero, &zero );
    }

  | _RAISE __IDENTIFIER
    {
	ssize_t zero = 0;
	ssize_t minus_one = -1;
	DNODE *exception = vartab_lookup( snail_cc->vartab, $2 );
	ssize_t exception_val = exception ? dnode_ssize_value( exception ) : 0;

	if( !exception ) {
	    yyerrorf( "Exception '%s' is not defined at this point", $2 );
	}

	snail_emit( snail_cc, px, "\tce\n", LDC, &minus_one );
	snail_emit( snail_cc, px, "\tc\n", PLDZ );
	snail_emit( snail_cc, px, "\tcee\n", RAISE, &zero, &exception_val );
    }
  | _RAISE __IDENTIFIER '(' expression ')'
    {
	ssize_t zero = 0;
	DNODE *exception = vartab_lookup( snail_cc->vartab, $2 );
	ssize_t exception_val = exception ? dnode_ssize_value( exception ) : 0;

	compiler_check_raise_expression( snail_cc, $2, px );

        if( tnode_is_reference( enode_type( snail_cc->e_stack ))) {
            snail_emit( snail_cc, px, "\tce\n", LLDC, &zero );
            snail_emit( snail_cc, px, "\tc\n", SWAP );            
        } else {
            snail_emit( snail_cc, px, "\tc\n", PLDZ );
        }
        snail_emit( snail_cc, px, "\tcee\n", RAISE, &zero, &exception_val );

	compiler_drop_top_expression( snail_cc );
    }

  | _RAISE __IDENTIFIER '(' expression ','
    {
	compiler_check_raise_expression( snail_cc, $2, px );
	if( !snail_stack_top_is_integer( snail_cc )) {
	    yyerrorf( "The first expression in 'raise' operator "
		      "must be of integer type" );
	}
    }
    expression ')'
    {
	ssize_t zero = 0;
	DNODE *exception = vartab_lookup( snail_cc->vartab, $2 );
	ssize_t exception_val = exception ? dnode_ssize_value( exception ) : 0;

	compiler_check_raise_expression( snail_cc, $2, px );
	if( !snail_stack_top_is_reference( snail_cc )) {
	    yyerrorf( "The second expression in 'raise' operator "
		      "must be of string type" );
	}

	compiler_drop_top_expression( snail_cc );
	compiler_drop_top_expression( snail_cc );
	snail_emit( snail_cc, px, "\tcee\n", RAISE, &zero, &exception_val );
    }

  | _RERAISE
    {
	if( !snail_cc->try_variable_stack || snail_cc->try_block_level < 1 ) {
	    yyerror( "'reraise' operator can only be used after "
		     "a try block" );
	} else {
	    ssize_t try_var_offset = snail_cc->try_variable_stack ?
		snail_cc->try_variable_stack[snail_cc->try_block_level-1] : 0;

	    snail_emit( snail_cc, px, "\tce\n", RERAISE, &try_var_offset );
	}
    }
;

exception_declaration
  : _EXCEPTION __IDENTIFIER
    { snail_compile_next_exception( snail_cc, $2, px ); }
  ;

/*--------------------------------------------------------------------------*/
/* package and import statements */

package_name
  : __IDENTIFIER
      {
	  DNODE *package_dnode = new_dnode_package( $1, px );
	  $$ = package_dnode;
      }
  ;

package_statement
  : _PACKAGE package_name
      {
	  vartab_insert_named( snail_cc->vartab, $2, px );
	  compiler_begin_package( snail_cc, share_dnode( $2 ), px );
      }
    statement_list
    '}' _PACKAGE __IDENTIFIER
      {
	  char *name;
	  if( snail_cc->current_package &&
	      (name = dnode_name( snail_cc->current_package )) != NULL ) {
	      if( strcmp( $7, name ) != 0 ) {
		  yyerrorf( "package '%s' ends with 'end package %s'",
			    name, $7 );
	      }
	  }
	  compiler_end_package( snail_cc, px );
      }
  ;

import_statement
   : _IMPORT __IDENTIFIER
       { $$ = $2; }
   ;

use_statement
   : _USE __IDENTIFIER
       { $$ = $2; }
   ;

load_library_statement
   : _LOAD __STRING_CONST
       {
	   compiler_load_library( snail_cc, $2, "SL_OPCODES", px );
       }
   ;

include_statement
   : _INCLUDE __STRING_CONST
       { $$ = $2; }
   ;

program_statement
  : _PROGRAM __IDENTIFIER '(' argument_list ')'
     {
	 compiler_compile_program_args( snail_cc, $2, $4, NULL, px );
     }
  | _PROGRAM __IDENTIFIER '(' argument_list ')' ':' var_type_description
     {
	 compiler_compile_program_args( snail_cc, $2, $4, $7, px );
     }
  | _PROGRAM '(' argument_list ')'
     {
	 compiler_compile_program_args( snail_cc, NULL, $3, NULL, px );
     }
  | _PROGRAM '(' argument_list ')' ':' var_type_description
     {
	 compiler_compile_program_args( snail_cc, NULL, $3, $6, px );
     }
  | _PROGRAM ':' var_type_description
     {
	 compiler_compile_program_args( snail_cc, NULL, NULL, $3, px );
     }
  ;

variable_access_identifier
  : __IDENTIFIER
     {
	 $$ = snail_lookup_dnode( snail_cc, NULL, $1, "variable" );
     }
  | __IDENTIFIER __COLON_COLON __IDENTIFIER
     {
	 $$ = snail_lookup_dnode( snail_cc, $1, $3, "variable" );
     }
  ;

incdec_statement
  : variable_access_identifier __INC
      {
	  if( snail_variable_has_operator( snail_cc, $1, "incvar", 0 )) {
	      TNODE *var_type = dnode_type( $1 );
	      ssize_t var_offset = dnode_offset( $1 );

	      snail_compile_operator( snail_cc, var_type, "incvar", 0, px );
	      snail_emit( snail_cc, px, "eN\n", &var_offset, dnode_name( $1 ));
	  } else {
	      snail_compile_load_variable_value( snail_cc, $1, px );
	      snail_compile_unop( snail_cc, "++", px );
	      snail_compile_store_variable( snail_cc, $1, px );
	  }
      }
  | variable_access_identifier __DEC
      {
	  if( snail_variable_has_operator( snail_cc, $1, "decvar", 0 )) {
	      TNODE *var_type = dnode_type( $1 );
	      ssize_t var_offset = dnode_offset( $1 );

	      snail_compile_operator( snail_cc, var_type, "decvar", 0, px );
	      snail_emit( snail_cc, px, "eN\n", &var_offset, dnode_name( $1 ));
	  } else {
	      snail_compile_load_variable_value( snail_cc, $1, px );
	      snail_compile_unop( snail_cc, "--", px );
	      snail_compile_store_variable( snail_cc, $1, px );
	  }
      }
  | lvalue __INC
      {
	  snail_compile_dup( snail_cc, px );
	  snail_compile_ldi( snail_cc, px );
	  snail_compile_unop( snail_cc, "++", px );
	  snail_compile_sti( snail_cc, px );
      }
  | lvalue __DEC
      {
	  snail_compile_dup( snail_cc, px );
	  snail_compile_ldi( snail_cc, px );
	  snail_compile_unop( snail_cc, "--", px );
	  snail_compile_sti( snail_cc, px );
      }
  ;

print_expression_list
  : expression
      {
	  snail_compile_unop( snail_cc, ".", px );
      }
  | print_expression_list ',' expression
      {
	  snail_emit( snail_cc, px, "\tc\n", SPACE );
	  snail_compile_unop( snail_cc, ".", px );
      }
; 

output_expression_list
  : expression
      {
	  snail_compile_unop( snail_cc, "<", px );
      }
  | output_expression_list ',' expression
      {
	  snail_emit( snail_cc, px, "\tc\n", SPACE );
	  snail_compile_unop( snail_cc, "<", px );
      }
; 

io_statement
  : '.' print_expression_list
     {
	 snail_emit( snail_cc, px, "\tc\n", NEWLINE );
     }

  | '<' output_expression_list

  | '>' lvariable
     {
	 snail_compile_unop( snail_cc, ">", px );
     }

  | __RIGHT_TO_LEFT expression
     {
	 snail_compile_unop( snail_cc, "<<", px );
     }

  | __LEFT_TO_RIGHT lvariable
     {
	 snail_compile_unop( snail_cc, ">>", px );
     }

  | file_io_statement
    {
	snail_emit( snail_cc, px, "\tc\n", PDROP );
	compiler_drop_top_expression( snail_cc );
    }
  ;

file_io_statement

  : '<' expression '>' __RIGHT_TO_LEFT expression
      {
       snail_check_and_compile_top_operator( snail_cc, "<<", 2, px );
       snail_emit( snail_cc, px, "\n" );
      }

  | '<' expression '>'
      {
	  snail_push_thrcode( snail_cc, px );
      } 
    __LEFT_TO_RIGHT lvariable
      {
	  snail_compile_file_input_operator( snail_cc, px );
      }

  | file_io_statement __RIGHT_TO_LEFT expression
      {
        snail_check_and_compile_top_operator( snail_cc, "<<", 2, px );
        snail_emit( snail_cc, px, "\n" );
      }

  | file_io_statement __LEFT_TO_RIGHT
      {
        snail_push_thrcode( snail_cc, px );
      }
    lvariable
      {
	snail_compile_file_input_operator( snail_cc, px );
      }

  ;

variable_declaration_keyword
  : _VAR { $$ = 0; }
  | _READONLY { $$ = 1; }
  | _READONLY _VAR { $$ = 1; }
  ;

variable_declaration
  : variable_declaration_keyword variable_identifier_list ':' var_type_description
    {
     int readonly = $1;

     dnode_list_append_type( $2, $4 );
     dnode_list_assign_offsets( $2, &snail_cc->local_offset );
     snail_vartab_insert_named_vars( snail_cc, $2, px );
     if( readonly ) {
	 dnode_list_set_flags( $2, DF_IS_READONLY );
     }
     if( snail_cc->loops ) {
	 snail_compile_zero_out_stackcells( snail_cc, $2, px );
     }
    }
  | variable_declaration_keyword
    variable_identifier_list ':' var_type_description initialiser
    {
     int readonly = $1;

     dnode_list_append_type( $2, $4 );
     dnode_list_assign_offsets( $2, &snail_cc->local_offset );
     snail_vartab_insert_named_vars( snail_cc, $2, px );
     if( readonly ) {
	 dnode_list_set_flags( $2, DF_IS_READONLY );
     }
     {
	 DNODE *var;
	 DNODE *lst = $2;
	 int len = dnode_list_length( lst );

	 foreach_dnode( var, lst ) {
	     if( --len <= 0 ) break;
	     snail_compile_dup( snail_cc, px );
	     snail_compile_initialise_variable( snail_cc, var, px );
	 }
	 snail_compile_initialise_variable( snail_cc, var, px );
     }
    }

  | variable_declaration_keyword var_type_description variable_declarator_list
      {
        int readonly = $1;

	dnode_list_append_type( $3, $2 );
	dnode_list_assign_offsets( $3, &snail_cc->local_offset );
	snail_vartab_insert_named_vars( snail_cc, $3, px );
	if( readonly ) {
	    dnode_list_set_flags( $3, DF_IS_READONLY );
	}
	if( snail_cc->loops ) {
	    snail_compile_zero_out_stackcells( snail_cc, $3, px );
	}
	snail_compile_variable_initialisations( snail_cc, $3, px );
      }

  | variable_declaration_keyword 
    compact_type_description dimension_list variable_declarator_list
      {
        int readonly = $1;

	tnode_append_element_type( $3, $2 );
	dnode_list_append_type( $4, $3 );
	dnode_list_assign_offsets( $4, &snail_cc->local_offset );
	snail_vartab_insert_named_vars( snail_cc, $4, px );
	if( readonly ) {
	    dnode_list_set_flags( $4, DF_IS_READONLY );
	}
	if( snail_cc->loops ) {
	    snail_compile_zero_out_stackcells( snail_cc, $4, px );
	}
	snail_compile_variable_initialisations( snail_cc, $4, px );
      }

  | variable_declaration_keyword
    variable_identifier_list initialiser
    {
     TNODE *expr_type = snail_cc->e_stack ?
	 share_tnode( enode_type( snail_cc->e_stack )) : NULL;
     int readonly = $1;

     dnode_list_append_type( $2, expr_type );
     dnode_list_assign_offsets( $2, &snail_cc->local_offset );
     snail_vartab_insert_named_vars( snail_cc, $2, px );
     if( readonly ) {
	 dnode_list_set_flags( $2, DF_IS_READONLY );
     }
     {
	 DNODE *var;
	 DNODE *lst = $2;
	 int len = dnode_list_length( lst );

	 foreach_dnode( var, lst ) {
	     if( --len <= 0 ) break;
	     snail_compile_dup( snail_cc, px );
	     snail_compile_initialise_variable( snail_cc, var, px );
	 }
	 snail_compile_initialise_variable( snail_cc, var, px );
     }
    }
  ;

variable_declarator_list
  : variable_declarator
  | variable_declarator '=' expression
      { $$ = dnode_set_flags( $1, DF_HAS_INITIALISER ); }
  | variable_declarator_list ',' variable_declarator
      { $$ = dnode_append( $3, $1 ); /* build list in the inverted order */ }
  | variable_declarator_list ',' variable_declarator '=' expression
      {
	dnode_set_flags( $3, DF_HAS_INITIALISER );
	$$ = dnode_append( $3, $1 ); /* build list in the inverted order */ 
      }
  ;

uninitialised_var_declarator_list
  : variable_declarator
  | uninitialised_var_declarator_list ',' variable_declarator
      { $$ = dnode_append( $1, $3 ); }
  ;

variable_declarator
  : variable_identifier
  | variable_identifier dimension_list
      { $$ = dnode_insert_type( $1, $2 ); }
  ;

variable_identifier_list
  : variable_identifier
    { $$ = $1; }
  | variable_identifier_list ',' variable_identifier
    { $$ = dnode_append( $1, $3 ); }
  ;

return_statement
  : _RETURN
      {
	snail_push_guarding_retval( snail_cc, px );
	snail_compile_return( snail_cc, 0, px );
      }
  | _RETURN 
      {
	if( snail_cc->loops ) {
            char *name = dnode_name( snail_cc->loops );
	    snail_drop_loop_counters( snail_cc, name, 0, px );
	}
        snail_push_guarding_retval( snail_cc, px );
      }
    expression_list
      { snail_compile_return( snail_cc, $3, px ); }
  ;

variable_identifier
  : __IDENTIFIER
     { $$ = new_dnode_name( $1, px ); }
  ;

/*--------------------------------------------------------------------------*/

opt_label
  : __IDENTIFIER ':'
      { $$ = $1; }
  |
      { $$ = NULL; }
  ;

if_condition
  : _IF /* expression */ condition
      {
        snail_push_relative_fixup( snail_cc, px );
	snail_compile_jz( snail_cc, 0, px );
      }
  ;

for_variable_declaration
  : variable_identifier ':' var_type_description
      {
	  dnode_append_type( $1, $3 );
	  dnode_assign_offset( $1, &snail_cc->local_offset );
	  $$ = $1;
      }
  | var_type_description variable_identifier
      {
	  dnode_append_type( $2, $1 );
	  dnode_assign_offset( $2, &snail_cc->local_offset );
	  $$ = $2;
      }
  | variable_identifier
      {
	  $$ = $1;
      }
  ;

control_statement
  : if_condition _THEN statement_list _ENDIF
      {
        snail_fixup_here( snail_cc );
      }

  | if_condition _THEN statement_list
      {
	ssize_t zero = 0;
        snail_push_relative_fixup( snail_cc, px );
        snail_emit( snail_cc, px, "\tce\n", JMP, &zero );
        snail_swap_fixups( snail_cc );
        snail_fixup_here( snail_cc );
      }
    _ELSE statement_list _ENDIF
      {
        snail_fixup_here( snail_cc );
      }

  | if_condition compound_statement
      {
        snail_fixup_here( snail_cc );
      }

  | if_condition compound_statement _ELSE 
      {
	ssize_t zero = 0;
        snail_push_relative_fixup( snail_cc, px );
        snail_emit( snail_cc, px, "\tce\n", JMP, &zero );
        snail_swap_fixups( snail_cc );
        snail_fixup_here( snail_cc );
      }
    compound_statement
      {
        snail_fixup_here( snail_cc );
      }

  | opt_label _WHILE
      {
	  ssize_t zero = 0;
	  snail_push_loop( snail_cc, $1, px );
          snail_push_relative_fixup( snail_cc, px );
	  snail_emit( snail_cc, px, "\tce\n", JMP, &zero );
	  snail_push_current_address( snail_cc, px );
	  snail_push_thrcode( snail_cc, px );
      }
    condition
      {
	snail_swap_thrcodes( snail_cc );
      }
    loop_body
      {
        snail_fixup_here( snail_cc );
	snail_fixup_op_continue( snail_cc, px );
	snail_merge_top_thrcodes( snail_cc, px );
	snail_compile_jnz( snail_cc, snail_pop_offset( snail_cc, px ), px );
	snail_fixup_op_break( snail_cc, px );
	snail_pop_loop( snail_cc );
      }

  | opt_label _FOR
      {
	snail_begin_subscope( snail_cc, px );
      } 
    '(' statement ';'
      {
	snail_push_loop( snail_cc, $1, px );
	snail_push_thrcode( snail_cc, px );
      }
    condition ';'
      {
	snail_push_thrcode( snail_cc, px );
      }
    statement ')'
      {
        ssize_t zero = 0;
	snail_push_thrcode( snail_cc, px );
        snail_push_relative_fixup( snail_cc, px );
	snail_emit( snail_cc, px, "\tce\n", JMP, &zero );
      }
    loop_body
      {
	snail_fixup_op_continue( snail_cc, px );
	snail_merge_top_thrcodes( snail_cc, px );

        snail_fixup_here( snail_cc );
	snail_merge_top_thrcodes( snail_cc, px );

	snail_compile_jnz( snail_cc, -snail_code_length( snail_cc ) + 2, px );

	snail_swap_thrcodes( snail_cc );
	snail_merge_top_thrcodes( snail_cc, px );
	snail_fixup_op_break( snail_cc, px );
	snail_pop_loop( snail_cc );
	snail_end_subscope( snail_cc, px );
      }

  | opt_label _FOR lvariable
      {
	snail_push_loop( snail_cc, $1, px );
	dnode_set_flags( snail_cc->loops, DF_LOOP_HAS_VAL );
	snail_compile_dup( snail_cc, px );
      }
    '=' expression
      {
        snail_compile_sti( snail_cc, px );
      }
    _TO expression
      {
	snail_compile_over( snail_cc, px );
	snail_compile_ldi( snail_cc, px );
	snail_compile_over( snail_cc, px );
	if( compiler_test_top_types_are_identical( snail_cc, px )) {
	    snail_compile_binop( snail_cc, ">", px );
	    snail_push_relative_fixup( snail_cc, px );
	    snail_compile_jnz( snail_cc, 0, px );
	} else {
	    ssize_t zero = 0;
	    compiler_drop_top_expression( snail_cc );
	    compiler_drop_top_expression( snail_cc );
	    snail_push_relative_fixup( snail_cc, px );
	    snail_emit( snail_cc, px, "\tce\n", JMP, &zero );
	}

        snail_push_current_address( snail_cc, px );
      }
     loop_body
      {
	snail_fixup_here( snail_cc );
	snail_fixup_op_continue( snail_cc, px );
	snail_compile_loop( snail_cc, snail_pop_offset( snail_cc, px ), px );
	snail_fixup_op_break( snail_cc, px );
	snail_pop_loop( snail_cc );
      }

  | opt_label _FOR variable_declaration_keyword
      {
	snail_begin_subscope( snail_cc, px );
      }
    for_variable_declaration
      {
	int readonly = $3;
	if( readonly ) {
	    dnode_set_flags( $5, DF_IS_READONLY );
	}
	snail_push_loop( snail_cc, $1, px );
	dnode_set_flags( snail_cc->loops, DF_LOOP_HAS_VAL );
      }
    '=' expression
      {
	DNODE *loop_counter = $5;

	if( dnode_type( loop_counter ) == NULL ) {
	    dnode_append_type( loop_counter,
			       share_tnode( enode_type( snail_cc->e_stack )));
	    dnode_assign_offset( loop_counter, &snail_cc->local_offset );
	}
	snail_vartab_insert_named_vars( snail_cc, loop_counter, px );
        snail_compile_store_variable( snail_cc, loop_counter, px );
	snail_compile_load_variable_address( snail_cc, loop_counter, px );
      }
    _TO expression
      {
	snail_compile_over( snail_cc, px );
	snail_compile_ldi( snail_cc, px );
	snail_compile_over( snail_cc, px );
	if( compiler_test_top_types_are_identical( snail_cc, px )) {
	    snail_compile_binop( snail_cc, ">", px );
	    snail_push_relative_fixup( snail_cc, px );
	    snail_compile_jnz( snail_cc, 0, px );
	} else {
	    ssize_t zero = 0;
	    compiler_drop_top_expression( snail_cc );
	    compiler_drop_top_expression( snail_cc );
	    snail_push_relative_fixup( snail_cc, px );
	    snail_emit( snail_cc, px, "\tce\n", JMP, &zero );
	}

        snail_push_current_address( snail_cc, px );
      }
     loop_body
      {
	snail_fixup_here( snail_cc );
	snail_fixup_op_continue( snail_cc, px );
	snail_compile_loop( snail_cc, snail_pop_offset( snail_cc, px ), px );
	snail_fixup_op_break( snail_cc, px );
	snail_pop_loop( snail_cc );
	snail_end_subscope( snail_cc, px );
      }

  | _TRY
      {
	cexception_t inner;
	ssize_t zero = 0;
	ssize_t try_var_offset = snail_cc->local_offset--;

	push_ssize_t( &snail_cc->try_variable_stack, &snail_cc->try_block_level,
		      try_var_offset, px );

	push_ssize_t( &snail_cc->catch_jumpover_stack,
		      &snail_cc->catch_jumpover_stack_length,
		      snail_cc->catch_jumpover_nr, px );

	snail_cc->catch_jumpover_nr = 0;

	cexception_guard( inner ) {
	    snail_push_relative_fixup( snail_cc, &inner );
	    snail_emit( snail_cc, px, "\tcee\n", TRY, &zero, &try_var_offset );
	}
	cexception_catch {
	    cexception_reraise( inner, px );
	}
      }
    compound_statement
      {
	ssize_t zero = 0;
	snail_emit( snail_cc, px, "\tc\n", RESTORE );
	snail_push_relative_fixup( snail_cc, px );
	snail_emit( snail_cc, px, "\tce\n", JMP, &zero );
	snail_swap_fixups( snail_cc );
	snail_fixup_here( snail_cc );
      }
    opt_catch_list
      {
	int i;

	for( i = 0; i < snail_cc->catch_jumpover_nr; i ++ ) { 
	    snail_fixup_here( snail_cc );
	}
	
	snail_cc->catch_jumpover_nr = 
	    pop_ssize_t( &snail_cc->catch_jumpover_stack, 
			 &snail_cc->catch_jumpover_stack_length, px );

	snail_fixup_here( snail_cc );
	pop_ssize_t( &snail_cc->try_variable_stack,
		     &snail_cc->try_block_level, px );
      }

  ;

compound_statement
  : '{'
      {
	snail_begin_subscope( snail_cc, px );
      }
    statement_list '}'
      {
	snail_end_subscope( snail_cc, px );
      }
  ;

loop_body
  : _DO
      {
	snail_begin_subscope( snail_cc, px );
      }
    statement_list
      {
	snail_end_subscope( snail_cc, px );
      }
    _ENDDO
  | compound_statement
  ;

opt_catch_list
  : catch_list
  | /* empty */
  ; 

catch_list
  : catch_statement
  | catch_list catch_statement
  ;

catch_var_identifier
  : __IDENTIFIER
    {
     char *opname = "exceptionval";
     ssize_t try_var_offset = snail_cc->try_variable_stack ?
	 snail_cc->try_variable_stack[snail_cc->try_block_level-1] : 0;
     DNODE *catch_var = vartab_lookup( snail_cc->vartab, $1 );
     TNODE *catch_var_type = catch_var ? dnode_type( catch_var ) : NULL;

     if( !catch_var_type ||
	     !tnode_lookup_operator( catch_var_type, opname, 1 )) {
	 yyerrorf( "type of variable in a 'catch' clause must "
		   "have unary '%s' operator", opname );
     } else {
	 snail_emit( snail_cc, px, "\n\tce\n", PLD, &try_var_offset );
	 snail_push_type( snail_cc, new_tnode_ref( px ), px );
	 snail_check_and_compile_operator( snail_cc, catch_var_type,
					   opname, /*arity:*/1,
					   /*fixup_values:*/ NULL,
					   px );
	 snail_emit( snail_cc, px, "\n" );
	 snail_compile_variable_assignment( snail_cc, catch_var, px );
     }
    }
  ;

catch_variable_declaration
  : _VAR variable_identifier_list ':' var_type_description
    {
     char *opname = "exceptionval";
     ssize_t try_var_offset = snail_cc->try_variable_stack ?
	 snail_cc->try_variable_stack[snail_cc->try_block_level-1] : 0;

     dnode_list_append_type( $2, $4 );
     dnode_list_assign_offsets( $2, &snail_cc->local_offset );     
     if( $2 && dnode_list_length( $2 ) > 1 ) {
	 yyerrorf( "only one variable may be declared in the 'catch' clause" );
     }
     if( !$4 || !tnode_lookup_operator( $4, opname, 1 )) {
	 yyerrorf( "type of variable declared in a 'catch' clause must "
		   "have unary '%s' operator", opname );
     } else {
	 snail_emit( snail_cc, px, "\n\tce\n", PLD, &try_var_offset );
	 snail_push_type( snail_cc, new_tnode_ref( px ), px );
	 snail_check_and_compile_operator( snail_cc, $4, opname,
					   /*arity:*/1,
					   /*fixup_values:*/ NULL, px );
	 snail_emit( snail_cc, px, "\n" );
	 snail_compile_variable_assignment( snail_cc, $2, px );	 
     }
     vartab_insert_named_vars( snail_cc->vartab, $2, px );
    }
  ;

catch_variable_list
  : catch_var_identifier
  | catch_variable_declaration
  | catch_variable_list ';' catch_var_identifier
  | catch_variable_list ';' catch_variable_declaration
;

exception_identifier_list
  : __IDENTIFIER
    {
      snail_emit_catch_comparison( snail_cc, NULL, $1, px );
      $$ = 0;
    }
  | __IDENTIFIER __COLON_COLON __IDENTIFIER
    {
      snail_emit_catch_comparison( snail_cc, $1, $3, px );
      $$ = 0;
    }
  | exception_identifier_list ',' __IDENTIFIER
    {
      ssize_t zero = 0;
      snail_push_relative_fixup( snail_cc, px );
      snail_emit( snail_cc, px, "\tce\n", BJNZ, &zero );
      snail_emit_catch_comparison( snail_cc, NULL, $3, px );
      $$ = $1 + 1;
    }
  | exception_identifier_list ',' __IDENTIFIER __COLON_COLON __IDENTIFIER
    {
      ssize_t zero = 0;
      snail_push_relative_fixup( snail_cc, px );
      snail_emit( snail_cc, px, "\tce\n", BJNZ, &zero );
      snail_emit_catch_comparison( snail_cc, $3, $5, px );
      $$ = $1 + 1;
    }
  ;

catch_statement
  : _CATCH
    compound_statement
      {
	ssize_t zero = 0;
	snail_cc->catch_jumpover_nr ++;
	snail_push_relative_fixup( snail_cc, px );
	snail_emit( snail_cc, px, "\tce\n", JMP, &zero );
      }

  | _CATCH
      {
	snail_begin_subscope( snail_cc,  px );
      }
    '(' catch_variable_list ')'
    compound_statement
      {
	ssize_t zero = 0;
	snail_cc->catch_jumpover_nr ++;
	snail_push_relative_fixup( snail_cc, px );
	snail_emit( snail_cc, px, "\tce\n", JMP, &zero );
	snail_end_subscope( snail_cc, px );
      }

  | _CATCH exception_identifier_list
      {
	snail_finish_catch_comparisons( snail_cc, $2, px );
	snail_begin_subscope( snail_cc,  px );
      }
    '(' catch_variable_list ')'  
    compound_statement
      {
	snail_end_subscope( snail_cc, px );
	snail_finish_catch_block( snail_cc, px );
      }

  | _CATCH exception_identifier_list
      {
	snail_finish_catch_comparisons( snail_cc, $2, px );
      }
    compound_statement
      {
	snail_finish_catch_block( snail_cc, px );
      }

;

/*--------------------------------------------------------------------------*/

compact_type_description
  : delimited_type_description
  | undelimited_or_structure_description
  ;

var_type_description
  : delimited_type_description
  | undelimited_or_structure_description
  | _ARRAY
    { $$ = new_tnode_array_snail( NULL, snail_cc->typetab, px ); }
  ;

undelimited_or_structure_description
  : struct_description
  | class_description
  | struct_or_class_description_body
  | undelimited_type_description
  ;

type_identifier
  : __IDENTIFIER
     {
	 $$ = snail_lookup_tnode( snail_cc, NULL, $1, "type" );
     }
  | __IDENTIFIER __COLON_COLON __IDENTIFIER
     {
	 $$ = snail_lookup_tnode( snail_cc, $1, $3, "type" );
     }
  ;

delimited_type_description
  : type_identifier
    { 
       $$ = share_tnode( $1 );
    }

  | _LIKE type_identifier struct_or_class_description_body
    {
	$$ = new_tnode_synonim( share_tnode( $2 ), px );
	$$ = tnode_move_operators( $$, $3 );
	delete_tnode( $3 );
	$3 = NULL;
	assert( snail_cc->current_type );
	tnode_set_suffix( $$, tnode_name( snail_cc->current_type ), px );
    }

  | type_identifier _OF delimited_type_description
    {
      TNODE *composite = $1;
      $$ = new_tnode_synonim( composite, px );
      tnode_set_kind( $$, TK_COMPOSITE );
      tnode_insert_element_type( $$, $3 );
    }
  | _ADDRESSOF
    { $$ = new_tnode_addressof( NULL, px ); }

  | _ARRAY _OF delimited_type_description
    { $$ = new_tnode_array_snail( $3, snail_cc->typetab, px ); }

  | _ARRAY dimension_list _OF delimited_type_description
    { $$ = tnode_append_element_type( $2, $4 ); }

  | _TYPE __IDENTIFIER
    {
	char *type_name = $2;
	TNODE *tnode = typetab_lookup( snail_cc->typetab, type_name );
	if( !tnode ) {
	    tnode = new_tnode_placeholder( type_name, px );
	    tnode_set_size( tnode, 1 );
	    typetab_insert( snail_cc->typetab, type_name, tnode, px );
	}
	$$ = share_tnode( tnode );
    }

  | function_or_procedure_type_keyword '(' argument_list ')'
    {
	int is_function = $1;
	TNODE *base_type = typetab_lookup( snail_cc->typetab, "procedure" );

	share_tnode( base_type );
	$$ = new_tnode_function_or_proc_ref( $3, NULL, base_type, px );
	if( is_function ) {
	    snail_set_function_arguments_readonly( $$ );
	}
    }
  | function_or_procedure_type_keyword '(' argument_list ')'
    __ARROW '(' retval_description_list ')'
    {
	int is_function = $1;
	TNODE *base_type = typetab_lookup( snail_cc->typetab, "procedure" );

	share_tnode( base_type );
	$$ = new_tnode_function_or_proc_ref( $3, $7, base_type, px );
	if( is_function ) {
	    snail_set_function_arguments_readonly( $$ );
	}
    }

  | _BLOB
    { $$ = new_tnode_blob_snail( snail_cc->typetab, px ); }
  ;


function_or_procedure_type_keyword
  : _FUNCTION
      { $$ = 1; }
  | _PROCEDURE
      { $$ = 0; }
  ;

opt_base_type
  : ':' type_identifier
      { $$ = $2; }
  | /* empty */
      { $$ = NULL; }
;

struct_description
  : _STRUCT struct_or_class_description_body
    {
      $$ = tnode_finish_struct( $2, px );
    }
;

class_description
  : _CLASS struct_or_class_description_body
    {
      compiler_compile_virtual_method_table( snail_cc, $2, px );
      $$ = tnode_finish_class( $2, px );
    }
;

undelimited_type_description
  : _ARRAY _OF undelimited_or_structure_description
    { $$ = new_tnode_array_snail( $3, snail_cc->typetab, px ); }

  | _ARRAY dimension_list _OF undelimited_or_structure_description
    { $$ = tnode_append_element_type( $2, $4 ); }

  | type_identifier _OF undelimited_or_structure_description
    {
      TNODE *composite = $1;
      $$ = new_tnode_synonim( composite, px );
      tnode_insert_element_type( $$, $3 );
    }

  | '(' var_type_description ')'
    { $$ = $2; }

  | _ENUM __IDENTIFIER '(' enum_member_list ')'
    {
      TNODE *enum_implementing_type = typetab_lookup( snail_cc->typetab, $2 );
      ssize_t tsize = enum_implementing_type ?
	  tnode_size( enum_implementing_type ) : 0;

      if( snail_cc->current_type &&
	      tnode_is_forward( snail_cc->current_type )) {
	  tnode_set_kind( snail_cc->current_type, TK_ENUM );
	  tnode_set_size( snail_cc->current_type, tsize );
      }
      $$ = tnode_finish_enum( $4, NULL, enum_implementing_type, px );
      compiler_check_enum_attributes( $$ );
    }

  | '(' __THREE_DOTS ',' enum_member_list ')'
    {
      if( !snail_cc->current_type ||
	  tnode_is_forward( snail_cc->current_type )) {
	  yyerror( "one can only extend previously defined enumeration types" );
	  tnode_set_size( $4, 1 );
      }
      $$ = $4;
    }
  ;

enum_member_list
  : enum_member
     {
       $$ = new_tnode( px );
       tnode_set_kind( $$, TK_ENUM );
       if( snail_cc->current_type ) {
	   tnode_merge_field_lists( $$, snail_cc->current_type );
       }
       tnode_insert_enum_value( $$, $1 );
     }

  | enum_member_list ',' enum_member
     { $$ = tnode_insert_enum_value( $1, $3 ); }
;

enum_member
  : __IDENTIFIER
    {
	$$ = new_dnode_name( $1, px );
    }
  | __IDENTIFIER '=' constant_integer_expression
    {
	$$ = new_dnode_name( $1, px );
	dnode_set_offset( $$, $3 );
    }
  | __THREE_DOTS
    {
	$$ = new_dnode_name( "...", px );
    }
  | /* empty */
    { $$ = NULL; }
  ;

struct_or_class_declaration_body
  : opt_base_type '{' struct_declaration_field_list finish_fields '}'
    { $$ = $3; }
  | opt_base_type '{' struct_declaration_field_list finish_fields 
    struct_operator_list '}'
    { $$ = $3; }
  | opt_base_type '{' struct_declaration_field_list finish_fields 
    struct_operator_list ';' '}'
    { $$ = $3; }
  ;

finish_fields
  : 
  {
      TNODE *current_class = $<tnode>0;
      TNODE *base_type = $<tnode>-2 ?
          $<tnode>-2 : typetab_lookup( snail_cc->typetab, "struct" );

      if( current_class != base_type ) {
	  tnode_insert_base_type( current_class, share_tnode( base_type ));
      }

      $$ = current_class;
  }
;

struct_declaration_field_list
  : struct_field
     {
	 assert( snail_cc->current_type );
	 $$ = share_tnode( snail_cc->current_type );
         tnode_insert_type_member( $$, $1 );
     }
  | type_attribute
     {
       cexception_t inner;

       cexception_guard( inner ) {
	   assert( snail_cc->current_type );
	   $$ = share_tnode( snail_cc->current_type );
	   tnode_set_attribute( $$, $1, &inner );
       }
       cexception_catch {
	   delete_anode( $1 );
	   cexception_reraise( inner, px );
       }
       delete_anode( $1 );
     }
  | struct_declaration_field_list ';' struct_field
     {
         $$ = tnode_insert_type_member( $1, $3 );
     }
  | struct_declaration_field_list ';' type_attribute
     {
       cexception_t inner;

       cexception_guard( inner ) {
	   $$ = $1;
	   tnode_set_attribute( $$, $3, &inner );
       }
       cexception_catch {
	   delete_anode( $3 );
	   cexception_reraise( inner, px );
       }
       delete_anode( $3 );
     }
  ;

struct_or_class_description_body
  : opt_base_type '{' struct_description_field_list finish_fields '}'
    { $$ = $3; }
  | opt_base_type '{' struct_description_field_list finish_fields 
    struct_operator_list '}'
    { $$ = $3; }
  | opt_base_type '{' struct_description_field_list finish_fields
    struct_operator_list ';' '}'
    { $$ = $3; }
  ;

struct_description_field_list
  : struct_field
     {
	 $$ = new_tnode( px );
         tnode_insert_type_member( $$, $1 );
     }
  | type_attribute
     {
       cexception_t inner;

       cexception_guard( inner ) {
	   $$ = new_tnode( &inner );
	   tnode_set_attribute( $$, $1, &inner );
       }
       cexception_catch {
	   delete_anode( $1 );
	   cexception_reraise( inner, px );
       }
       delete_anode( $1 );
     }
  | struct_description_field_list ';' struct_field
     {
         $$ = tnode_insert_type_member( $1, $3 );
     }
  | struct_description_field_list ';' type_attribute
     {
       cexception_t inner;

       cexception_guard( inner ) {
	   $$ = $1;
	   tnode_set_attribute( $$, $3, &inner );
       }
       cexception_catch {
	   delete_anode( $3 );
	   cexception_reraise( inner, px );
       }
       delete_anode( $3 );
     }
  ;

struct_field
  : struct_var_declaration  { $$ = $1; }
  |                         { $$ = NULL; }
  ;

struct_operator_list
  : struct_operator
    {
	TNODE *struct_type = $<tnode>-1;
	tnode_insert_type_member( struct_type, $1 );
	$$ = struct_type;
    }
  | struct_operator_list struct_operator
    {
	tnode_insert_type_member( $1, $2 );
	$$ = $1;
    }
  | struct_operator_list ';' struct_operator
    {
	tnode_insert_type_member( $1, $3 );
	$$ = $1;
    }
;

struct_operator
  : operator_definition
  | method_definition
  | method_header
  ;

struct_var_declaration
  : variable_identifier_list ':' var_type_description
      {
       $$ = dnode_list_append_type( $1, $3 );
      }
  | _VAR variable_identifier_list ':' var_type_description
      {
       $$ = dnode_list_append_type( $2, $4 );
      }

  | _CONST variable_identifier_list ':' var_type_description
      {
       $$ = dnode_list_append_type( $2, $4 );
       $$ = dnode_list_set_flags( $$, DF_IS_READONLY );
      }

  | _VAR var_type_description uninitialised_var_declarator_list
      {
        $$ = dnode_list_append_type( $3, $2 );
      }

  | var_type_description uninitialised_var_declarator_list
      {
        $$ = dnode_list_append_type( $2, $1 );
      }

  | _VAR compact_type_description dimension_list
    uninitialised_var_declarator_list
      {
	tnode_append_element_type( $3, $2 );
	$$ = dnode_list_append_type( $4, $3 );
      }

  | compact_type_description dimension_list uninitialised_var_declarator_list
      {
	tnode_append_element_type( $2, $1 );
	$$ = dnode_list_append_type( $3, $2 );
      }
  ;

size_constant
  : _SIZEOF type_identifier
    {
      TNODE *tnode = $2;

      if( tnode ) {
	  $$ = tnode_size( tnode );
      }
    }
  | _SIZEOF _NATIVE __STRING_CONST
    {
      $$ = compiler_native_type_size( $3 );
    }
  | _NATIVE __STRING_CONST /* _REF */ '*'
    {
      $$ = compiler_native_type_nreferences( $2 );
    }
  ;

type_attribute
  : __IDENTIFIER
    { $$ = new_anode_integer_attribute( $1, 1, px ); }
  | __IDENTIFIER '=' __INTEGER_CONST
    { $$ = new_anode_integer_attribute( $1, atol( $3 ), px ); }
  | __IDENTIFIER '=' size_constant
    { $$ = new_anode_integer_attribute( $1, $3, px ); }
  | __IDENTIFIER '=' __IDENTIFIER
    { $$ = new_anode_string_attribute( $1, $3, px ); }
  | __IDENTIFIER '=' __STRING_CONST
    { $$ = new_anode_string_attribute( $1, $3, px ); }
  ;

dimension_list
  : '[' ']'
    { $$ = new_tnode_array_snail( NULL, snail_cc->typetab, px ); }
  | dimension_list '[' ']'
    {
      TNODE *array_type = new_tnode_array_snail( NULL, snail_cc->typetab, px );
      $$ = tnode_append_element_type( $1, array_type );
    }
  ;

/*--------------------------------------------------------------------------*/

/* type_declaration */

type_declaration_name
  : __IDENTIFIER
    { $$ = $1; }

  | _STRUCT
    { $$ = "struct"; }

  | _ARRAY
    { $$ = "array"; }

  | _PROCEDURE
    { $$ = "procedure"; }

  | _BLOB
    { $$ = "blob"; }
;

type_declaration_start
  : _TYPE type_declaration_name
      {
	TNODE *old_tnode = typetab_lookup( snail_cc->typetab, $2 );
	TNODE *tnode = NULL;

	if( !old_tnode || !tnode_is_extendable_enum( old_tnode )) {
	    TNODE *tnode = new_tnode_forward( $2, px );
	    snail_typetab_insert( snail_cc, tnode, px );
	}
	tnode = typetab_lookup( snail_cc->typetab, $2 );
	assert( !snail_cc->current_type );
	snail_cc->current_type = tnode;
	snail_begin_scope( snail_cc, px );
      }
;

delimited_type_declaration
  : type_declaration_start '=' delimited_type_description
      {
	snail_end_scope( snail_cc, px );
	snail_compile_type_declaration( snail_cc, $3, px );
      }
  | type_declaration_start '=' delimited_type_description /*type_*/initialiser
      {
        snail_compile_drop( snail_cc, px );
	snail_end_scope( snail_cc, px );
	snail_compile_type_declaration( snail_cc, $3, px );
      }
  | type_declaration_start
      {
	snail_end_scope( snail_cc, px );
	snail_cc->current_type = NULL;
      }
  | forward_struct_declaration
  | forward_class_declaration
  ;

undelimited_type_declaration
  : type_declaration_start '=' undelimited_type_description
      {
	snail_end_scope( snail_cc, px );
	snail_compile_type_declaration( snail_cc, $3, px );
	snail_cc->current_type = NULL;
      }

  | type_declaration_start '=' undelimited_type_description type_initialiser
      {
	snail_end_scope( snail_cc, px );
	snail_compile_type_declaration( snail_cc, $3, px );
	snail_cc->current_type = NULL;
      }

  | _TYPE __IDENTIFIER _OF __IDENTIFIER '='
      {
	TNODE * volatile base = NULL;
	TNODE * volatile tnode = NULL;
	cexception_t inner;

	// snail_begin_scope( snail_cc, px );

	cexception_guard( inner ) {
	    base = new_tnode_placeholder( $4, &inner );
	    tnode = new_tnode_composite( $2, base, &inner );
	    tnode_set_flags( tnode, TF_IS_FORWARD );
	    snail_typetab_insert( snail_cc, tnode, &inner );
	    tnode = typetab_lookup( snail_cc->typetab, $2 );
	    snail_cc->current_type = tnode;
	    snail_typetab_insert( snail_cc, share_tnode( base ), &inner );
	    snail_begin_scope( snail_cc, &inner );
	}
	cexception_catch {
	    delete_tnode( base );
	    delete_tnode( tnode );
	    cexception_reraise( inner, px );
	}
      }
    undelimited_type_description
      {
	snail_end_scope( snail_cc, px );
	snail_compile_type_declaration( snail_cc, $7, px );
	snail_cc->current_type = NULL;
      }

  | struct_declaration
  | class_declaration
  ;

struct_declaration
  : _STRUCT __IDENTIFIER
    {
	TNODE *old_tnode = typetab_lookup( snail_cc->typetab, $2 );
	TNODE *tnode = NULL;

	if( !old_tnode ) {
	    TNODE *tnode = new_tnode_forward_struct( $2, px );
	    snail_typetab_insert( snail_cc, tnode, px );
	}
	tnode = typetab_lookup( snail_cc->typetab, $2 );
	assert( !snail_cc->current_type );
	snail_cc->current_type = tnode;
	snail_begin_scope( snail_cc, px );
    }
    struct_or_class_declaration_body
    {
	tnode_finish_struct( $4, px );
	snail_end_scope( snail_cc, px );
	snail_typetab_insert( snail_cc, $4, px );
        snail_cc->current_type = NULL;
    }
  | type_declaration_start '=' _STRUCT
    {
	assert( snail_cc->current_type );
	tnode_set_flags( snail_cc->current_type, TF_IS_REF );
        tnode_set_kind( snail_cc->current_type, TK_STRUCT );
    }
    struct_or_class_declaration_body
    {
	tnode_finish_struct( $5, px );
	snail_end_scope( snail_cc, px );
	snail_compile_type_declaration( snail_cc, $5, px );
        snail_cc->current_type = NULL;
    }
  | type_declaration_start '='
    {
	assert( snail_cc->current_type );
	// tnode_set_flags( snail_cc->current_type, TF_IS_REF );
    }
    struct_or_class_declaration_body
    {
	// tnode_finish_struct( $4, px );
	snail_end_scope( snail_cc, px );
	snail_compile_type_declaration( snail_cc, $4, px );
        snail_cc->current_type = NULL;
    }
  | _TYPE __IDENTIFIER _OF __IDENTIFIER '=' _STRUCT 
      {
	TNODE * volatile base = NULL;
	TNODE * volatile tnode = NULL;
	cexception_t inner;

	// snail_begin_scope( snail_cc, px );

	cexception_guard( inner ) {
	    base = new_tnode_placeholder( $4, &inner );
	    tnode = new_tnode_composite( $2, base, &inner );
	    tnode_set_flags( tnode, TF_IS_FORWARD );
	    snail_typetab_insert( snail_cc, tnode, &inner );
	    tnode = typetab_lookup( snail_cc->typetab, $2 );
	    snail_cc->current_type = tnode;
	    snail_typetab_insert( snail_cc, share_tnode( base ), &inner );
	    snail_begin_scope( snail_cc, &inner );
	}
	cexception_catch {
	    delete_tnode( base );
	    delete_tnode( tnode );
	    cexception_reraise( inner, px );
	}
      }
      struct_or_class_declaration_body
      {
	snail_end_scope( snail_cc, px );
	snail_compile_type_declaration( snail_cc, $8, px );
	snail_cc->current_type = NULL;
      }

  | _TYPE __IDENTIFIER _OF __IDENTIFIER '='
      {
	TNODE * volatile base = NULL;
	TNODE * volatile tnode = NULL;
	cexception_t inner;

	// snail_begin_scope( snail_cc, px );

	cexception_guard( inner ) {
	    base = new_tnode_placeholder( $4, &inner );
	    tnode = new_tnode_composite( $2, base, &inner );
	    tnode_set_flags( tnode, TF_IS_FORWARD );
	    snail_typetab_insert( snail_cc, tnode, &inner );
	    tnode = typetab_lookup( snail_cc->typetab, $2 );
	    snail_cc->current_type = tnode;
	    snail_typetab_insert( snail_cc, share_tnode( base ), &inner );
	    snail_begin_scope( snail_cc, &inner );
	}
	cexception_catch {
	    delete_tnode( base );
	    delete_tnode( tnode );
	    cexception_reraise( inner, px );
	}
      }
    struct_or_class_declaration_body
      {
	snail_end_scope( snail_cc, px );
	snail_compile_type_declaration( snail_cc, $7, px );
	snail_cc->current_type = NULL;
      }

;

class_declaration
  : _CLASS __IDENTIFIER
    {
	TNODE *old_tnode = typetab_lookup( snail_cc->typetab, $2 );
	TNODE *tnode = NULL;

	if( !old_tnode ) {
	    TNODE *tnode = new_tnode_forward_class( $2, px );
	    snail_typetab_insert( snail_cc, tnode, px );
	}
	tnode = typetab_lookup( snail_cc->typetab, $2 );
	assert( !snail_cc->current_type );
	snail_cc->current_type = tnode;
	snail_begin_scope( snail_cc, px );
    }
    struct_or_class_declaration_body
    {
 	tnode_finish_class( $4, px );
	compiler_compile_virtual_method_table( snail_cc, $4, px );
	snail_end_scope( snail_cc, px );
	snail_typetab_insert( snail_cc, $4, px );
	snail_cc->current_type = NULL;
    }
  | type_declaration_start '=' _CLASS
    {
	assert( snail_cc->current_type );
	tnode_set_flags( snail_cc->current_type, TF_IS_REF );
        tnode_set_kind( snail_cc->current_type, TK_CLASS );
    }
    struct_or_class_declaration_body
    {
 	tnode_finish_class( $5, px );
	compiler_compile_virtual_method_table( snail_cc, $5, px );
	snail_end_scope( snail_cc, px );
	snail_compile_type_declaration( snail_cc, $5, px );
	snail_cc->current_type = NULL;
    }
;

forward_struct_declaration
  : _STRUCT __IDENTIFIER
      {
	  TNODE *tnode = new_tnode_forward_struct( $2, px );
	  snail_typetab_insert( snail_cc, tnode, px );
      }
;

forward_class_declaration
  : _CLASS __IDENTIFIER
      {
	  TNODE *tnode = new_tnode_forward_class( $2, px );
	  snail_typetab_insert( snail_cc, tnode, px );
      }
;


initialiser
  : '=' expression
  ;

type_initialiser
  : '=' '(' expression ')'
  ;

/*--------------------------------------------------------------------------*/

/*

1) compound assignment statements:
a[i] = b + c;

2) multiple assignments:
( a[i], b, c ) = b + c, d, f( x, y );
( a, b ) = f( x, y, z );
  a, b   = f( x, y, z );

*/

lvalue_list
: lvalue
      {
	  snail_push_thrcode( snail_cc, px );
	  $$ = 1;
      }
| __IDENTIFIER
      {
	  snail_push_varaddr_expr( snail_cc, $1, px );
	  snail_push_thrcode( snail_cc, px );
	  $$ = 1;
      }
| lvalue_list ',' lvalue
      {
	  snail_push_thrcode( snail_cc, px );
	  $$ = $1 + 1;
      }
| lvalue_list ',' __IDENTIFIER
      {
	  snail_push_varaddr_expr( snail_cc, $3, px );
	  snail_push_thrcode( snail_cc, px );
	  $$ = $1 + 1;
      }
;

assignment_statement
  : variable_access_identifier '=' expression
      {
	  snail_compile_store_variable( snail_cc, $1, px );
      }
  | lvalue '=' expression
      {
	  snail_compile_sti( snail_cc, px );
      }
  | '('
      {
	  /* Values must be emmitted first in the code. */
	  snail_push_thrcode( snail_cc, px );
      }
    lvalue_list ')' '=' multivalue_expression_list
      {
	  snail_compile_multiple_assignment( snail_cc, $3, $3, $6, px );
      }

  | lvalue ',' 
      {
	  snail_push_thrcode( snail_cc, px );
      }
    lvalue_list '=' multivalue_expression_list
      {
	  snail_compile_multiple_assignment( snail_cc, $4+1, $4, $6, px );
	  snail_compile_sti( snail_cc, px );
      }

  | __IDENTIFIER ',' 
      {
	  snail_push_varaddr_expr( snail_cc, $1, px );
	  snail_push_thrcode( snail_cc, px );
      }
    lvalue_list '=' multivalue_expression_list
      {
	  snail_compile_multiple_assignment( snail_cc, $4+1, $4, $6, px );

	  {
	      DNODE *var;

	      compiler_swap_top_expressions( snail_cc );
	      var = enode_variable( snail_cc->e_stack );

	      share_dnode( var );
	      compiler_drop_top_expression( snail_cc );
	      snail_compile_variable_assignment( snail_cc, var, px );
	      delete_dnode( var );
	  }
      }

  | variable_access_identifier
      {
	  snail_compile_load_variable_value( snail_cc, $1, px );
      }
    __ARITHM_ASSIGN expression
      { 
	snail_compile_binop( snail_cc, $3, px );
	snail_compile_store_variable( snail_cc, $1, px );
      }
  | lvalue
      {
	  snail_compile_dup( snail_cc, px );
	  snail_compile_ldi( snail_cc, px );
      }
    __ARITHM_ASSIGN expression
      { 
	  snail_compile_binop( snail_cc, $3, px );
	  snail_compile_sti( snail_cc, px );
      }

  | lvalue
      {
	  snail_compile_ldi( snail_cc, px );
      }
     __ASSIGN expression
      {
	  int err = 0;
	  if( !snail_test_top_types_are_assignment_compatible(
	           snail_cc, px )) {
	      yyerrorf( "incopatible types for value-copy assignment ':='" );
	  }
	  snail_emit( snail_cc, px, "\tc\n", COPY );
	  if( !err && !snail_stack_top_is_reference( snail_cc )) {
	      yyerrorf( "value assignemnt := works only for references" );
	      err = 1;
	  }
	  if( !err &&
	      !snail_test_top_types_are_readonly_compatible_for_copy(
	           snail_cc, px )) {
	      yyerrorf( "can not copy readonly value in the value-copy "
			"assignment ':='" );
	      err = 1;
	  }
	  compiler_drop_top_expression( snail_cc );
	  if( !err && !snail_stack_top_is_reference( snail_cc )) {
	      yyerrorf( "value assignemnt := works only for references" );
	      err = 1;
	  }
	  compiler_drop_top_expression( snail_cc );
      }

  | variable_access_identifier
      {
	  snail_compile_load_variable_value( snail_cc, $1, px );
      }
    __ASSIGN expression
      {
	  int err = 0;
	  if( !snail_test_top_types_are_assignment_compatible(
	           snail_cc, px )) {
	      yyerrorf( "incopatible types for value-copy assignment ':='" );
	      err = 1;
	  }
	  snail_emit( snail_cc, px, "\tc\n", COPY );
	  if( !err && !snail_stack_top_is_reference( snail_cc )) {
	      yyerrorf( "value assignemnt := works only for references" );
	      err = 1;
	  }
	  if( !err &&
	      !snail_test_top_types_are_readonly_compatible_for_copy(
	           snail_cc, px )) {
	      yyerrorf( "can not copy readonly value in the value-copy "
			"assignment ':='" );
	      err = 1;
	  }
	  compiler_drop_top_expression( snail_cc );
	  if( !err && !snail_stack_top_is_reference( snail_cc )) {
	      yyerrorf( "value assignemnt := works only for references" );
	      err = 1;
	  }
	  compiler_drop_top_expression( snail_cc );
      }
  ;

bytecode_statement
  : _BYTECODE '{' bytecode_sequence '}'
  ;

bytecode_sequence
  : bytecode_item
  | bytecode_sequence bytecode_item
  ;

bytecode_item
  : opcode
  | variable_reference
  | bytecode_constant
  ;

opcode
  : __IDENTIFIER
      { snail_emit( snail_cc, px, "\tC\n", $1 ); }
  | __IDENTIFIER __COLON_COLON __IDENTIFIER
      { snail_emit( snail_cc, px, "\tMC\n", $1, $3 ); }
  ;

variable_reference
  : '%' __IDENTIFIER
      { 
         DNODE *varnode = vartab_lookup( snail_cc->vartab, $2 );
	 if( varnode ) {
	     ssize_t var_offset = dnode_offset( varnode );
             snail_emit( snail_cc, px, "\teN\n", &var_offset, $2 );
	 } else {
	     yyerrorf( "name '%s' not declared in the current scope", $2 );
	 }
      }
  ;

bytecode_constant
  : __INTEGER_CONST
      {
	  ssize_t val = atol( $1 );
	  snail_emit( snail_cc, px, "\te\n", &val );
      }
  | '+' __INTEGER_CONST
      {
	  ssize_t val = atol( $2 );
	  snail_emit( snail_cc, px, "\te\n", &val );
      }
  | '-' __INTEGER_CONST
      {
	  ssize_t val = -atol( $2 );
	  snail_emit( snail_cc, px, "\te\n", &val );
      }
  | __REAL_CONST
      {
	double val;
	sscanf( $1, "%lf", &val );
        snail_emit( snail_cc, px, "\tf\n", val );
      }
  | __STRING_CONST
      {
	ssize_t string_offset;
	string_offset = compiler_assemble_static_string( snail_cc, $1, px );
        snail_emit( snail_cc, px, "\te\n", &string_offset );
      }

  | __DOUBLE_PERCENT __IDENTIFIER
      {
	static const ssize_t zero = 0;
        snail_emit( snail_cc, px, "\te\n", &zero );
	if( !snail_cc->current_function ) {
	    yyerrorf( "type attribute '%%%%%s' is not available here "
		      "(are you compiling a function or operator?)", $2 );
	} else {
	    FIXUP *type_attribute_fixup =
		new_fixup_absolute( $2, thrcode_length( snail_cc->thrcode ) - 1,
				    NULL /* next */, px );

	    dnode_insert_code_fixup( snail_cc->current_function,
				     type_attribute_fixup );
	}
      }

  | _CONST '(' constant_expression ')'
      {
	  const_value_t const_expr = $3;

	  switch( const_expr.value_type ) {
	  case VT_INT: {
	      ssize_t val = const_expr.value.i;
	      snail_emit( snail_cc, px, "\te\n", &val );
	      }
	      break;
	  case VT_FLOAT: {
	      double val = const_expr.value.f;
	      snail_emit( snail_cc, px, "\tf\n", &val );
	      }
	      break;
	  default:
	      yyerrorf( "constant of type '%s' is not supported "
			"in bytecode", cvalue_type_name( const_expr ));
	      break;
	  }
      }     
  ;

function_identifier
  : __IDENTIFIER
	{
	    snail_check_and_push_function_name( snail_cc, NULL, $1, px );
	}
  | __IDENTIFIER __COLON_COLON __IDENTIFIER
	{
	    snail_check_and_push_function_name( snail_cc, $1, $3, px );
	}
  ;

multivalue_function_call
  : function_identifier 
        {
	  TNODE *fn_tnode;

	  fn_tnode = snail_cc->current_call ?
	      dnode_type( snail_cc->current_call ) : NULL;

	  snail_cc->current_arg = fn_tnode ?
	      dnode_list_last( tnode_args( fn_tnode )) : NULL;

	  snail_push_guarding_arg( snail_cc, px );
	}
    '(' opt_actual_argument_list ')'
        {
	    DNODE *function = snail_cc->current_call;
	    TNODE *fn_tnode = function ? dnode_type( function ) : NULL;

	    if( fn_tnode && tnode_kind( fn_tnode ) == TK_FUNCTION_REF ) {
		char *fn_name = dnode_name( function );
		ssize_t offset = dnode_offset( function );
		snail_emit( snail_cc, px, "\tceN\n", PLD, &offset, fn_name );
	    }

	    $$ = snail_compile_multivalue_function_call( snail_cc, px );
	}
  | lvalue 
        {
	  TNODE *fn_tnode = NULL;

	  snail_compile_ldi( snail_cc, px );

	  snail_emit( snail_cc, px, "\tc\n", RTOR );

	  fn_tnode = snail_cc->e_stack ?
	      enode_type( snail_cc->e_stack ) : NULL;

	  dlist_push_dnode( &snail_cc->current_call_stack,
			    &snail_cc->current_call, px );

	  dlist_push_dnode( &snail_cc->current_arg_stack,
			    &snail_cc->current_arg, px );

	  snail_cc->current_call = new_dnode( px );
	  if( fn_tnode ) {
	      dnode_insert_type( snail_cc->current_call,
				 share_tnode( fn_tnode ));
	  }
	  if( fn_tnode && tnode_kind( fn_tnode ) != TK_FUNCTION_REF ) {
	      yyerrorf( "called object is not a function pointer" );
	  }

	  snail_cc->current_arg = fn_tnode ?
	      dnode_list_last( tnode_args( fn_tnode )) : NULL;

	  snail_push_guarding_arg( snail_cc, px );
	}
    '(' opt_actual_argument_list ')'
        {
	    snail_emit( snail_cc, px, "\tc\n", RFROMR );
	    $$ = snail_compile_multivalue_function_call( snail_cc, px );
	}
  | variable_access_identifier
    __ARROW __IDENTIFIER
        {
            DNODE *object = $1;
            TNODE *object_type = dnode_type( object );
            DNODE *method = tnode_lookup_field( object_type, $3 );

	    if( method ) {
		TNODE *fn_tnode = dnode_type( method );

		dlist_push_dnode( &snail_cc->current_call_stack,
				  &snail_cc->current_call, px );

		dlist_push_dnode( &snail_cc->current_arg_stack,
				  &snail_cc->current_arg, px );

		snail_cc->current_call = share_dnode( method );

		if( fn_tnode && tnode_kind( fn_tnode ) != TK_METHOD ) {
		    yyerrorf( "called field is not a method" );
		}

		snail_cc->current_arg = fn_tnode ?
		    dnode_prev( dnode_list_last( tnode_args( fn_tnode ))) :
		    NULL;
	    } else {
		char *object_name = object ? dnode_name( object ) : NULL;
		char *method_name = $3;
		char *class_name =
		    object_type ? tnode_name( object_type ) : NULL;

		if( object_name && method_name ) {
		    yyerrorf( "object '%s' does not have method '%s'",
			      object_name, method_name );
		} else if ( class_name && method_name ) {
		    yyerrorf( "type/class '%s' does not have method '%s'",
			      class_name, method_name );
		} else {
		    yyerrorf( "can not locate method '%s'", method_name );
		}
	    }
	    snail_push_guarding_arg( snail_cc, px );
	    snail_compile_load_variable_value( snail_cc, object, px );
	}
    '(' opt_actual_argument_list ')'
        {
	    snail_compile_load_variable_value( snail_cc, $1, px );
	    compiler_drop_top_expression( snail_cc );
	    $$ = snail_compile_multivalue_function_call( snail_cc, px );
	}

  | lvalue 
        {
	    snail_compile_ldi( snail_cc, px );
            snail_compile_dup( snail_cc, px );
            snail_emit( snail_cc, px, "\tc\n", RTOR );
	    compiler_drop_top_expression( snail_cc );
	}
    __ARROW __IDENTIFIER
        {
            ENODE *object_expr = snail_cc->e_stack;;
            TNODE *object_type =
		object_expr ? enode_type( object_expr ) : NULL;
            DNODE *method =
		object_type ? tnode_lookup_field( object_type, $4 ) : NULL;

	    if( method ) {
		TNODE *fn_tnode = dnode_type( method );

		dlist_push_dnode( &snail_cc->current_call_stack,
				  &snail_cc->current_call, px );

		dlist_push_dnode( &snail_cc->current_arg_stack,
				  &snail_cc->current_arg, px );

		snail_cc->current_call = share_dnode( method );

		if( fn_tnode && tnode_kind( fn_tnode ) != TK_METHOD ) {
		    yyerrorf( "called field is not a method" );
		}

		snail_cc->current_arg = fn_tnode ?
		    dnode_prev( dnode_list_last( tnode_args( fn_tnode ))) :
		    NULL;
	    }
            snail_push_guarding_arg( snail_cc, px );
            compiler_swap_top_expressions( snail_cc );
	}
    '(' opt_actual_argument_list ')'
        {
	    snail_emit( snail_cc, px, "\tc\n", RFROMR );
	    $$ = snail_compile_multivalue_function_call( snail_cc, px );
	}

  ;

function_call
  : multivalue_function_call
    {
	if( $1 > 0 ) {
	    snail_emit_drop_returned_values( snail_cc, $1 - 1, px );
	} else {
	    yyerrorf( "functions called in exressions must return "
		      "at least one value" );
	    /* Push NULL value to maintain stack value balance and
	       avoid segfaults or asserts in the downstream code: */
	    snail_push_type( snail_cc, new_tnode_nullref( px ), px );
	}
    }
  ;

opt_actual_argument_list
  : actual_argument_list
  |
  ;

actual_argument_list
  : expression
      {
	snail_convert_function_argument( snail_cc, px );
      }
  | __IDENTIFIER 
      {
	  snail_emit_default_arguments( snail_cc, $1, px );
      }
   __THICK_ARROW expression
      {
	snail_convert_function_argument( snail_cc, px );
      }
  | actual_argument_list ',' expression
      {
	snail_convert_function_argument( snail_cc, px );
      }
  | actual_argument_list ',' __IDENTIFIER
      {
	  snail_emit_default_arguments( snail_cc, $3, px );
      }
    __THICK_ARROW expression
      {
	  snail_convert_function_argument( snail_cc, px );
      }
  ;

expression_list
  : expression
      { $$ = 1; }
  | expression_list ',' expression
      { $$ = $1 + 1; }
  ;

condition
  : function_call
  | simple_expression
/*
  | arithmetic_expression
*/
  | boolean_expression
  | '(' simple_expression ')'
  | '(' function_call ')'
  ;

multivalue_expression_list
  : multivalue_expression
      { $$ = $1; }
  | multivalue_expression_list ',' multivalue_expression
      { $$ = $1 + $3; }
  ;

expression
  : function_call
  | simple_expression
  | arithmetic_expression
  | boolean_expression
  | assignment_expression
  | null_expression
  ;

multivalue_expression
  : multivalue_function_call
      { $$ = $1; }
  | simple_expression
      { $$ = 1; }
  | arithmetic_expression
      { $$ = 1; }
  | boolean_expression
      { $$ = 1; }
  | assignment_expression
      { $$ = 1; }
  ;

null_expression
  : _NULL
      {
	  TNODE *tnode = new_tnode_nullref( px );
	  snail_push_type( snail_cc, tnode, px );
	  snail_emit( snail_cc, px, "\tc\n", PLDZ );
      }
  ;

simple_expression
  : constant
  | variable
  | field_access
      {
	snail_compile_ldi( snail_cc, px );
      }
  | indexed_rvalue
  | _BYTECODE ':' var_type_description '{' bytecode_sequence '}'
      {
	snail_push_type( snail_cc, $3, px );
      }
  | generator_new
  | array_expression
  | struct_expression
  | unpack_expression
  ;

opt_comma
  : ','
  |
  ;

/* unpack  int (  a,    20,     4  );
   //--    type,  blob, offset, size
*/
unpack_expression
  : _UNPACK compact_type_description
    '(' expression ',' expression ',' expression ')'
  {
      TNODE *type = $2;
      if( tnode_kind( type ) == TK_ARRAY ) {
	  snail_check_and_compile_operator( snail_cc,
					    tnode_element_type( type ),
					    "unpackarray", 3 /* arity */,
					    NULL /* fixup_values */, px );
      } else {
	  snail_check_and_compile_operator( snail_cc, type,
					    "unpack", 3 /* arity */,
					    NULL /* fixup_values */, px );
      }
      snail_emit( snail_cc, px, "\n" );
  }
  | _UNPACK compact_type_description '[' ']'
    '(' expression ',' expression ',' expression ')'
  {
      TNODE *element_type = $2;
      snail_check_and_compile_operator( snail_cc, element_type,
					"unpackarray", 3 /* arity */,
					NULL /* fixup_values */, px );

      snail_emit( snail_cc, px, "\n" );
  }
  | _UNPACK compact_type_description md_array_allocator '[' ']' 
    /*  blob,          offset,        format_and_size */
    /*  b,             123,           "i4x10" */
    '(' expression ',' expression ',' expression ')'
  {
      char *operator_name = "unpackmdarray";
      int arity = 3;
      int level = $3;
      TNODE *element_type = $2;
      TNODE *array_tnode =
	  new_tnode_array_snail( NULL, snail_cc->typetab, px );

      if( tnode_lookup_operator( element_type, operator_name, arity )) {
          key_value_t *fixup_values =
              make_mdalloc_key_value_list( element_type, level );
	  snail_check_and_compile_operator( snail_cc, element_type,
					    operator_name,
					    arity, fixup_values,
					    px );
	  /* Return value pushed by ..._compile_operator() function must
	     be dropped, since it only describes return value as having
	     type 'array'. The caller of the current function will push
	     a correct return value 'array of proper_element_type' */
	  compiler_drop_top_expression( snail_cc );
	  if( snail_stack_top_is_array( snail_cc )) {
	      snail_append_expression_type( snail_cc, array_tnode );
	      snail_append_expression_type( snail_cc, share_tnode( element_type ));
	  }
      } else {
	  compiler_drop_top_expression( snail_cc );
	  compiler_drop_top_expression( snail_cc );
	  compiler_drop_top_expression( snail_cc );
	  tnode_report_missing_operator( element_type, operator_name, arity );
      }
      snail_emit( snail_cc, px, "\n" );
  }
  ;

array_expression
  : '[' expression_list opt_comma ']'
     {
	 snail_compile_array_expression( snail_cc, $2, px );
     }

  | '{' expression_list opt_comma '}'

  ;

struct_expression
  : _STRUCT type_identifier
     {
	 snail_compile_alloc( snail_cc, share_tnode( $2 ), px );
     }
    '{' field_initialiser_list opt_comma '}'

  | _STRUCT type_identifier _OF delimited_type_description
     {
	 TNODE *composite = new_tnode_synonim( $2, px );
	 tnode_set_kind( composite, TK_COMPOSITE );
	 tnode_insert_element_type( composite, $4 );

	 snail_compile_alloc( snail_cc, share_tnode( composite ), px );
     }
    '{' field_initialiser_list opt_comma '}'

  ;

field_initialiser_list
  : field_initialiser
  | field_initialiser_list ',' field_initialiser
  ;

field_initialiser_separator
: ':'
| __THICK_ARROW
;

field_initialiser
  : __IDENTIFIER
     {
	 DNODE *field;
	 snail_compile_dup( snail_cc, px );
	 field = snail_make_stack_top_field_type( snail_cc, $1 );
	 snail_make_stack_top_addressof( snail_cc, px );
	 if( field && dnode_offset( field ) != 0 ) {
	     ssize_t field_offset = dnode_offset( field );
	     snail_emit( snail_cc, px, "\tce\n", OFFSET, &field_offset );
	 }
     }
    field_initialiser_separator expression
     {
	 snail_compile_sti( snail_cc, px );
     }
  ;

arithmetic_expression
  : expression '+' expression
      {
       snail_compile_binop( snail_cc, "+", px );
      }
  | expression '-' expression
      {
       snail_compile_binop( snail_cc, "-", px );
      }
  | expression '*' expression
      {
       snail_compile_binop( snail_cc, "*", px );
      }
  | expression '/' expression
      {
       snail_compile_binop( snail_cc, "/", px );
      }
  | expression '&' expression
      {
       snail_compile_binop( snail_cc, "&", px );
      }
  | expression '|' expression
      {
       snail_compile_binop( snail_cc, "|", px );
      }
  | expression __RIGHT_TO_LEFT expression /* << */
      {
       snail_compile_binop( snail_cc, "shl", px );
      }
  | expression __LEFT_TO_RIGHT expression /* >> */
      {
       snail_compile_binop( snail_cc, "shr", px );
      }
  | expression _SHL expression
      {
       snail_compile_binop( snail_cc, "shl", px );
      }
  | expression _SHR expression
      {
       snail_compile_binop( snail_cc, "shr", px );
      }
  | expression '^' expression
      {
       snail_compile_binop( snail_cc, "^", px );
      }
  | expression '%' expression
      {
       snail_compile_binop( snail_cc, "%", px );
      }
  | expression __STAR_STAR expression
      {
       snail_compile_binop( snail_cc, "**", px );
      }
  | expression '_' expression
      {
       snail_compile_binop( snail_cc, "_", px );
      }

  | '+' expression %prec __UNARY
      {
       snail_compile_unop( snail_cc, "+", px );
      }
  | '-' expression %prec __UNARY
      {
       snail_compile_unop( snail_cc, "-", px );
      }
  | '~' expression %prec __UNARY
      {
       snail_compile_unop( snail_cc, "~", px );
      }

  | expression __DOUBLE_PERCENT expression
      {
       snail_compile_binop( snail_cc, "%%", px );
      }

  | '<' __IDENTIFIER '>' expression %prec __UNARY
      {
       snail_compile_type_conversion( snail_cc, /*target_name*/$2, px );
      }

  | expression '@' __IDENTIFIER
      {
       snail_compile_type_conversion( snail_cc, /*target_name*/$3, px );
      }

  | expression '@' '(' var_type_description ')'
      {
       snail_compile_type_conversion( snail_cc, NULL, px );
      }

  | expression '?'
      {
        snail_push_relative_fixup( snail_cc, px );
	snail_compile_jz( snail_cc, 0, px );
      }
    expression ':'
      {
	ssize_t zero = 0;
        snail_push_relative_fixup( snail_cc, px );
        snail_emit( snail_cc, px, "\tce\n", JMP, &zero );
        snail_swap_fixups( snail_cc );
        snail_fixup_here( snail_cc );
      }
    expression
      {
	compiler_check_top_2_expressions_and_drop( snail_cc, "?:", px );
        snail_fixup_here( snail_cc );
      }
/*
  | expression _AS __IDENTIFIER
*/
  | '(' arithmetic_expression ')'
  | '(' simple_expression ')'

  ;

boolean_expression
  : expression '<' expression
      {
       snail_compile_binop( snail_cc, "<", px );
      }
  | expression '>' expression
      {
       snail_compile_binop( snail_cc, ">", px );
      }
  | expression __LE expression
      {
       snail_compile_binop( snail_cc, "<=", px );
      }
  | expression __GE expression
      {
       snail_compile_binop( snail_cc, ">=", px );
      }
  | expression __EQ expression
      {
       snail_compile_binop( snail_cc, "==", px );
      }
  | expression __NE expression
      {
       snail_compile_binop( snail_cc, "!=", px );
      }
  | expression _AND
      {
	snail_compile_dup( snail_cc, px );
        snail_push_relative_fixup( snail_cc, px );
	snail_compile_jz( snail_cc, 0, px );
	compiler_duplicate_top_expression( snail_cc, px );
	snail_compile_drop( snail_cc, px );
      }
    expression
      {
	compiler_check_top_2_expressions_and_drop( snail_cc, "and", px );
        snail_fixup_here( snail_cc );
      }
  | expression _OR
      {
	snail_compile_dup( snail_cc, px );
        snail_push_relative_fixup( snail_cc, px );
	snail_compile_jnz( snail_cc, 0, px );
	compiler_duplicate_top_expression( snail_cc, px );
	snail_compile_drop( snail_cc, px );
      }
    expression
      {
	compiler_check_top_2_expressions_and_drop( snail_cc, "or", px );
	snail_fixup_here( snail_cc );
      }
  | '!' expression %prec __UNARY
      {
       snail_compile_unop( snail_cc, "!", px );
      }

  | '(' boolean_expression ')'
  ;

generator_new
  : _NEW compact_type_description
      {
	snail_compile_alloc( snail_cc, $2, px );
      }
  | _NEW compact_type_description '[' expression ']'
      {
	snail_compile_array_alloc( snail_cc, $2, px );
      }
  | _NEW compact_type_description md_array_allocator '[' expression ']'
      {
	snail_compile_mdalloc( snail_cc, $2, $3, px );
      }
  | _NEW _ARRAY '[' expression ']' _OF var_type_description
      {
	snail_compile_array_alloc( snail_cc, $7, px );
      }
  | _NEW _ARRAY md_array_allocator '[' expression ']' _OF var_type_description
      {
	snail_compile_mdalloc( snail_cc, $8, $3, px );
      }
  | _NEW compact_type_description '[' expression ']' _OF var_type_description
      {
	snail_compile_composite_alloc( snail_cc, $2, $7, px );
      }
  | _NEW _BLOB '(' expression ')'
      {
	snail_compile_blob_alloc( snail_cc, px );
      }
  ;

md_array_allocator
  : '[' expression ']'
      {
	int level = 0;
	snail_compile_mdalloc( snail_cc, NULL, level, px );
	$$ = level + 1;
      }
  | md_array_allocator '[' expression ']'
      {
	int level = $1;
	snail_compile_mdalloc( snail_cc, NULL, level, px );
	$$ = level + 1;
      }
  ;

lvalue
  : function_call
  | field_access
  | indexed_lvalue
  ;

lvariable
  : variable_access_identifier
      { snail_compile_load_variable_address( snail_cc, $1, px ); }
  | lvalue
  ;

variable
  : variable_access_identifier
      {
	  DNODE *variable = $1;
	  TNODE *variable_type = variable ? dnode_type( variable ) : NULL; 

	  if( variable_type && tnode_kind( variable_type ) == TK_FUNCTION ) {
	      snail_compile_load_function_address( snail_cc, variable, px );
	  } else {
	      snail_compile_load_variable_value( snail_cc, variable, px );
	  }
      }
  ;

index_expression
  : expression
    { $$ = 1; }
  
  | expression __DOT_DOT expression
    { $$ = 2; }
  
  | expression __DOT_DOT 
    { $$ = -1; }
  
  | expression __THREE_DOTS 
    { $$ = -1; }
  
  | /* empty */
    { $$ = 0; }
;

variable_access_for_indexing
  : variable_access_identifier
      {
       if( snail_dnode_is_reference( snail_cc, $1 )) {
           snail_compile_load_variable_value( snail_cc, $1, px );
       } else {
           snail_compile_load_variable_address( snail_cc, $1, px );
       }
       $$ = $1;
      }
  ;

lvalue_for_indexing
  : lvalue
      {
       if( snail_stack_top_base_is_reference( snail_cc )) {
	   snail_compile_ldi( snail_cc, px );
       }
      }
  ;

indexed_rvalue
  : variable_access_for_indexing '[' index_expression ']'
      {
	  DNODE *var_dnode = $1;
	  TNODE *var_tnode = var_dnode ? dnode_type( var_dnode ) : NULL;
	  TNODE *element_type = var_tnode ?
	      tnode_element_type( var_tnode ) : NULL;
	  char *operator_name = "ldx";

	  if( element_type && tnode_is_reference( element_type )) {
	      operator_name = "pldx";
	  } else {
	      operator_name = "ldx";
	  }
	  if( snail_stack_top_has_operator( snail_cc, operator_name, 2 ) ||
 	      snail_nth_stack_value_has_operator( snail_cc, 1,
						  operator_name, 2 )) {
	      snail_check_and_compile_top_2_operator( snail_cc,
						      operator_name, 2, px );
	  } else {
	      if( snail_dnode_is_reference( snail_cc, var_dnode )) {
		  snail_compile_indexing( snail_cc, 1, $3, px );
	      } else {
		  snail_compile_indexing( snail_cc, 0, $3, px );
	      }
	      snail_compile_ldi( snail_cc, px );
	  }
      }
  | lvalue_for_indexing '[' index_expression ']'
      {
	  ENODE *top_expr = snail_cc->e_stack;
	  ENODE *top2_expr = top_expr ? enode_next( top_expr ) : NULL;
	  TNODE *top2_tnode = top2_expr ? enode_type( top2_expr ) : NULL;
	  TNODE *element_type = top2_tnode ?
	      tnode_element_type( top2_tnode ) : NULL;
	  char *operator_name = "ldx";

	  if( element_type && tnode_is_reference( element_type )) {
	      operator_name = "pldx";
	  } else {
	      operator_name = "ldx";
	  }
	  if( snail_stack_top_has_operator( snail_cc, operator_name, 2 ) ||
 	      snail_nth_stack_value_has_operator( snail_cc, 1, operator_name, 2 )) {
	      snail_check_and_compile_top_2_operator( snail_cc, operator_name, 2, px );
	  } else {
	      if( snail_stack_top_is_reference( snail_cc )) {
		  snail_compile_indexing( snail_cc, 1, $3, px );
	      } else {
		  snail_compile_indexing( snail_cc, 0, $3, px );
	      }
	      snail_compile_ldi( snail_cc, px );
	  }
      }
  ;

indexed_lvalue
  : variable_access_for_indexing '[' index_expression ']'
      {
	  if( snail_dnode_is_reference( snail_cc, $1 )) {
	      snail_compile_indexing( snail_cc, 1, $3, px );
	  } else {
	      snail_compile_indexing( snail_cc, 0, $3, px );
	  }
      }

  | lvalue_for_indexing '[' index_expression ']'
      {
	  if( snail_stack_top_is_reference( snail_cc )) {
	      snail_compile_indexing( snail_cc, 1, $3, px );
	  } else {
	      snail_compile_indexing( snail_cc, 0, $3, px );
	  }
      }
  ;

field_access
  : variable_access_identifier '.' __IDENTIFIER
      {
       DNODE *field;

       if( snail_dnode_is_reference( snail_cc, $1 )) {
	   snail_compile_load_variable_value( snail_cc, $1, px );
       } else {
           snail_compile_load_variable_address( snail_cc, $1, px );
       }
       field = snail_make_stack_top_field_type( snail_cc, $3 );
       snail_make_stack_top_addressof( snail_cc, px );
       if( field && dnode_offset( field ) != 0 ) {
	   ssize_t field_offset = dnode_offset( field );
	   snail_emit( snail_cc, px, "\tce\n", OFFSET, &field_offset );
       }
      }
  | lvalue '.' __IDENTIFIER
      {
       DNODE *field;

       if( snail_stack_top_base_is_reference( snail_cc )) {
	   snail_compile_ldi( snail_cc, px );
       }
       field = snail_make_stack_top_field_type( snail_cc, $3 );
       snail_make_stack_top_addressof( snail_cc, px );
       if( field && dnode_offset( field ) != 0 ) {
	   ssize_t field_offset = dnode_offset( field );
	   snail_emit( snail_cc, px, "\tce\n", OFFSET, &field_offset );
       }
      }
  ;

assignment_expression
  : lvalue '=' expression
      {
       snail_compile_swap( snail_cc, px );
       snail_compile_over( snail_cc, px );
       snail_compile_sti( snail_cc, px );
      }

  | variable_access_identifier '=' expression
      {
       snail_compile_dup( snail_cc, px );
       snail_compile_store_variable( snail_cc, $1, px );
      }

  | '(' assignment_expression ')'
  ;

constant
  : __INTEGER_CONST
      {
       snail_compile_constant( snail_cc, TS_INTEGER_SUFFIX,
			       NULL, NULL, "integer", $1, px );
      }
  | __INTEGER_CONST __IDENTIFIER
      {
       snail_compile_constant( snail_cc, TS_INTEGER_SUFFIX,
			       NULL, $2, "integer", $1, px );
      }
  | __INTEGER_CONST __IDENTIFIER __COLON_COLON __IDENTIFIER
      {
       snail_compile_constant( snail_cc, TS_INTEGER_SUFFIX,
			       $2, $4, "integer", $1, px );
      }
  | __REAL_CONST
      {
       snail_compile_constant( snail_cc, TS_FLOAT_SUFFIX,
			       NULL, NULL, "real", $1, px );
      }
  | __REAL_CONST __IDENTIFIER
      {
       snail_compile_constant( snail_cc, TS_FLOAT_SUFFIX,
			       NULL, $2, "real", $1, px );
      }
  | __REAL_CONST __IDENTIFIER __COLON_COLON __IDENTIFIER
      {
       snail_compile_constant( snail_cc, TS_FLOAT_SUFFIX,
			       $2, $4, "real", $1, px );
      }
  | __STRING_CONST
      {
       snail_compile_constant( snail_cc, TS_STRING_SUFFIX,
			       NULL, NULL, "string", $1, px );
      }
  | __STRING_CONST __IDENTIFIER
      {
       snail_compile_constant( snail_cc, TS_STRING_SUFFIX,
			       NULL, $2, "string", $1, px );
      }
  | __STRING_CONST __IDENTIFIER __COLON_COLON __IDENTIFIER
      {
       snail_compile_constant( snail_cc, TS_STRING_SUFFIX,
			       $2, $4, "string", $1, px );
      }
  | __IDENTIFIER  __IDENTIFIER
      {
       snail_compile_enumeration_constant( snail_cc, NULL, $1, $2, px );
      }

  | __IDENTIFIER  __IDENTIFIER __COLON_COLON __IDENTIFIER
      {
       snail_compile_enumeration_constant( snail_cc, $2, $1, $4, px );
      }

  | _CONST __IDENTIFIER
      {
	DNODE *const_dnode = snail_lookup_constant( snail_cc, NULL, $2,
						    "constant" );
	if( const_dnode ) {
	    char pad[80];

	    snprintf( pad, sizeof(pad), "%ld",
		      (long)dnode_ssize_value( const_dnode ));
	    snail_compile_constant( snail_cc, TS_INTEGER_SUFFIX,
				    NULL, NULL, "integer", pad, px );
	}
      }

  | _CONST __IDENTIFIER __COLON_COLON __IDENTIFIER
      {
	DNODE *const_dnode = snail_lookup_constant( snail_cc, $2, $4,
						    "constant" );
	if( const_dnode ) {
	    char pad[80];

	    snprintf( pad, sizeof(pad), "%ld",
		      (long)dnode_ssize_value( const_dnode ));
	    snail_compile_constant( snail_cc, TS_INTEGER_SUFFIX,
				    NULL, NULL, "integer", pad, px );
	}
      }

  | _CONST '(' constant_expression ')'
      {
	  snail_compile_multitype_const_value( snail_cc, &$3, NULL, NULL, px );
      }

  | _CONST '(' constant_expression ')' __IDENTIFIER
      {
	  snail_compile_multitype_const_value( snail_cc, &$3, NULL, $5, px );
      }

  | _CONST '(' constant_expression ')'
    __IDENTIFIER __COLON_COLON __IDENTIFIER
      {
	  snail_compile_multitype_const_value( snail_cc, &$3, $5, $7, px );
      }

  ;

argument_list
  : argument
    { $$ = $1; }
  | argument_list ';' argument
    /* build a list of names in reverse order (opposite to the order which
       they appear in a programm text): */
    { $$ = dnode_append( $3, $1 ); }
  | /* empty */
    { $$ = NULL; }
  ;

opt_readonly
  : _READONLY
    { $$ = 1; }
  |
    { $$ = 0; }
  ;

argument
  : opt_readonly argument_identifier_list ':' var_type_description
    {
	$$ = dnode_list_append_type( $2, $4 );
	if( $1 ) {
	    dnode_list_set_flags( $2, DF_IS_READONLY );
	}
    }

  | opt_readonly argument_identifier_list ':' var_type_description
        '=' constant_expression
    {
	DNODE *arg;

	$$ = dnode_list_append_type( $2, $4 );
	foreach_dnode( arg, $2 ) {
	    const_value_t val = make_zero_const_value();
	    const_value_copy( &val, &$6, px );
	    snail_check_default_value_compatibility( arg, &val );
	    dnode_set_value( arg, &val );
	    dnode_set_flags( arg, DF_HAS_INITIALISER );
	    if( $1 ) {
		dnode_set_flags( arg, DF_IS_READONLY );
	    }
	}
    }

  | opt_readonly var_type_description uninitialised_var_declarator_list
      {
	$$ = dnode_list_append_type( dnode_list_invert( $3 ), $2 );
	if( $1 ) {
	    dnode_list_set_flags( $3, DF_IS_READONLY );
	}
      }

  | opt_readonly var_type_description variable_declarator
        '=' constant_expression
      {
        $$ = dnode_list_append_type( $3, $2 );
	snail_check_default_value_compatibility( $3, &$5 );
	dnode_set_value( $3, &$5 );
	dnode_set_flags( $3, DF_HAS_INITIALISER );
	if( $1 ) {
	    dnode_set_flags( $3, DF_IS_READONLY );
	}
      }

  | opt_readonly
    compact_type_description dimension_list uninitialised_var_declarator_list
      {
	tnode_append_element_type( $3, $2 );
	$$ = dnode_list_append_type( dnode_list_invert( $4 ), $3 );
	if( $1 ) {
	    dnode_list_set_flags( $4, DF_IS_READONLY );
	}
      }

  | opt_readonly compact_type_description dimension_list variable_declarator
    '=' constant_expression
      {
	tnode_append_element_type( $3, $2 );
	$$ = dnode_list_append_type( $4, $3 );
	snail_check_default_value_compatibility( $4, &$6 );
	dnode_set_value( $4, &$6 );
	dnode_set_flags( $4, DF_HAS_INITIALISER );
	if( $1 ) {
	    dnode_set_flags( $4, DF_IS_READONLY );
	}
      }

  | opt_readonly __IDENTIFIER
      {
	  $$ = new_dnode_name( $2, px );
	  dnode_append_type( $$, new_tnode_ignored( px ));
	  if( $1 ) {
	      dnode_list_set_flags( $$, DF_IS_READONLY );
	  }
      }
  ;

argument_identifier_list
  : __IDENTIFIER
    { $$ = new_dnode_name( $1, px ); }
  | argument_identifier_list ',' __IDENTIFIER
    { $$ = dnode_append( new_dnode_name( $3, px ), $1 ); }
  ;

function_or_operator_start
  :
        {
	  cexception_t inner;
	  DNODE *volatile funct = $<dnode>0;
	  TNODE *function_type = funct ? dnode_type( funct ) : NULL;
	  int is_bytecode = dnode_has_flags( funct, DF_BYTECODE );

	  snail_cc->current_function = funct;

	  dnode_reset_flags( funct, DF_FNPROTO );
    	  cexception_guard( inner ) {
	      ssize_t current_address = thrcode_length( snail_cc->thrcode );
	      type_kind_t function_kind = function_type ?
		  tnode_kind( function_type ) : TK_NONE;

	      if( function_kind == TK_METHOD ) {
		  dnode_set_ssize_value( funct, current_address );
	      } else {
		  dnode_set_offset( funct, current_address );
	      }

	      snail_fixup_function_calls( snail_cc, funct );
	      snail_compile_main_thrcode( snail_cc );
	      snail_fixup_function_calls( snail_cc, funct );
	      snail_compile_function_thrcode( snail_cc );

	      snail_push_current_address( snail_cc, px );

	      if( !is_bytecode ) {
		  ssize_t zero = 0;
		  snail_push_absolute_fixup( snail_cc, px );
		  snail_emit( snail_cc, px, "\tce\n", ENTER, &zero );
	      }

              snail_begin_scope( snail_cc, &inner );
	  }
	  cexception_catch {
	      delete_dnode( funct );
	      snail_cc->current_function = NULL;
	      cexception_reraise( inner, px );
	  }
	  if( !is_bytecode ) {
	      snail_emit_function_arguments( funct, snail_cc, px );
	  }
	}
;

function_or_operator_end
  :
        {
	  DNODE *funct = snail_cc->current_function;
	  int is_bytecode = dnode_has_flags( funct, DF_BYTECODE );

	  if( !is_bytecode ) {
	      /* patch ENTER command: */
	      snail_fixup( snail_cc, -snail_cc->local_offset );
	  }

	  snail_get_inline_code( snail_cc, funct, px );

	  if( thrcode_last_opcode( snail_cc->thrcode ).fn != RET ) {
	      snail_emit( snail_cc, px, "\tc\n", RET );
	  }

	  snail_compile_main_thrcode( snail_cc );

	  snail_end_scope( snail_cc, px );
	  snail_cc->current_function = NULL;
	}
;

method_definition
  : method_header
    function_or_operator_start
    function_or_operator_body
    function_or_operator_end
  ;

function_definition
  : function_header
    function_or_operator_start
    function_or_operator_body
    function_or_operator_end
  ;

operator_definition
  : operator_header
    function_or_operator_start
    function_or_operator_body
    function_or_operator_end
  ;

function_or_operator_body
  : '{' statement_list '}'
  | '{' bytecode_sequence '}'
  ;

retval_description_list
  : var_type_description 
      { $$ = new_dnode_return_value( $1, px ); }
  | retval_description_list ',' var_type_description
      { $$ = dnode_append( $1, new_dnode_return_value( $3, px )); }
  ;

opt_retval_description_list
  : ':' retval_description_list { $$ = $2; }
  | __ARROW retval_description_list { $$ = $2; }
  | { $$ = NULL; }
  ;

function_attributes
  : _INLINE
    { $$ = DF_INLINE; }
  | _BYTECODE
    { $$ = DF_BYTECODE; }
  | _BYTECODE _INLINE
    { $$ = DF_BYTECODE | DF_INLINE; }
  | _INLINE _BYTECODE
    { $$ = DF_INLINE | DF_BYTECODE; }
  ;

opt_function_attributes
  : function_attributes
    { $$ = $1; }
  |
    { $$ = 0; }
;

function_code_start
  :
    {
      snail_compile_function_thrcode( snail_cc );
      if( thrcode_debug_is_on()) {
	  const char *currentLine = snail_flex_current_line();
	  const char *first_nonblank = currentLine;
	  while( isspace( *first_nonblank )) first_nonblank++;
	  if( *first_nonblank == '#' ) {
	      snail_printf( NULL, "%s\n", currentLine );
	  } else {
	      snail_printf( NULL, "#\n# %s\n#\n", currentLine );
	  }
      }
    }
  ;

function_or_procedure_keyword
  : function_code_start _FUNCTION
      { $$ = 1; }
  | function_code_start _PROCEDURE
      { $$ = 0; }
 ;

function_header
  : opt_function_attributes function_or_procedure_keyword
        {
	    //snail_begin_scope( snail_cc, px );
        }
             __IDENTIFIER '(' argument_list ')'
            opt_retval_description_list
        {
	  cexception_t inner;
	  DNODE *volatile funct = NULL;
	  int is_function = $2;

    	  cexception_guard( inner ) {
	      $$ = funct = new_dnode_function( $4, $6, $8, &inner );
	      $6 = NULL;
	      $8 = NULL;
	      dnode_set_flags( funct, DF_FNPROTO );
	      if( $1 & DF_BYTECODE )
	          dnode_set_flags( funct, DF_BYTECODE );
	      if( $1 & DF_INLINE )
	          dnode_set_flags( funct, DF_INLINE );
	      funct = $$ =
		  snail_check_and_set_fn_proto( snail_cc, funct, px );
	      if( is_function ) {
		  snail_set_function_arguments_readonly( dnode_type( funct ));
	      }
	  }
	  cexception_catch {
	      delete_dnode( $6 );
	      delete_dnode( $8 );
	      delete_dnode( funct );
	      $$ = NULL;
	      cexception_reraise( inner, px );
	  }
	}
  ;

method_header
  : opt_function_attributes function_code_start _METHOD
        {
	    //snail_begin_scope( snail_cc, px );
	}
             __IDENTIFIER '(' argument_list ')'
            opt_retval_description_list
        {
	  cexception_t inner;
	  DNODE *volatile funct = NULL;
          DNODE *volatile self_dnode = NULL;
          DNODE *parameter_list = $7;
	  int is_function = 0;

    	  cexception_guard( inner ) {
              self_dnode = new_dnode_name( "self", &inner );
#if 0
              dnode_insert_type( self_dnode,
                                 share_tnode( snail_cc->current_class ));
#else
              dnode_insert_type( self_dnode,
                                 share_tnode( $<tnode>-1 ));
#endif
              parameter_list = dnode_append( parameter_list, self_dnode );
              self_dnode = NULL;

	      $$ = funct = new_dnode_method( $5, parameter_list, $9, &inner );
	      $7 = NULL;
	      $9 = NULL;
	      dnode_set_flags( funct, DF_FNPROTO );
	      if( $1 & DF_BYTECODE )
	          dnode_set_flags( funct, DF_BYTECODE );
	      if( $1 & DF_INLINE )
	          dnode_set_flags( funct, DF_INLINE );
              dnode_set_scope( funct, snail_current_scope( snail_cc ));
	      funct = $$ =
		  snail_check_and_set_fn_proto( snail_cc, funct, px );
	      share_dnode( funct );
	      if( is_function ) {
		  snail_set_function_arguments_readonly( dnode_type( funct ));
	      }
	  }
	  cexception_catch {
	      delete_dnode( $7 );
	      delete_dnode( $9 );
	      delete_dnode( funct );
              delete_dnode( self_dnode );
	      $$ = NULL;
	      cexception_reraise( inner, px );
	  }
	}
  ;

operator_keyword
: function_code_start _OPERATOR
;

operator_header
  : opt_function_attributes operator_keyword
        {
	    //snail_begin_scope( snail_cc, px );
	}
            __STRING_CONST '(' argument_list ')'
            opt_retval_description_list
        {
	  cexception_t inner;
	  DNODE *volatile funct = NULL;

    	  cexception_guard( inner ) {
	      $$ = funct = new_dnode_operator( $4, $6, $8, &inner );
	      $6 = NULL;
	      $8 = NULL;
	      if( $1 & DF_BYTECODE )
		dnode_set_flags( funct, DF_BYTECODE );
	      if( $1 & DF_INLINE )
	          dnode_set_flags( funct, DF_INLINE );
	      $$ = funct;
	  }
	  cexception_catch {
	      delete_dnode( $6 );
	      delete_dnode( $8 );
	      delete_dnode( funct );
	      $$ = NULL;
	      cexception_reraise( inner, px );
	  }
	}
  ;

function_prototype
  : function_header
      { snail_compile_main_thrcode( snail_cc ); }
  | _FORWARD function_header
      { snail_compile_main_thrcode( snail_cc ); }
  ;

/*---------------------------------------------------------------------------*/

constant_declaration
  : _CONST __IDENTIFIER '=' constant_expression
    {
      DNODE *const_dnode = new_dnode_constant( $2, &$4, px );
      snail_consttab_insert_consts( snail_cc, const_dnode, px );
    }
;

constant_integer_expression
  : constant_expression
    {
	if( const_value_type( &$1 ) == VT_INT ) {
	    $$ = const_value_integer( &$1 );
	} else {
	    yyerrorf( "constant integer value required" );
	}
    }
;

field_designator
  : __IDENTIFIER '.' __IDENTIFIER
    {
	$$ = compiler_lookup_type_field( snail_cc, NULL, $1, $3 );
    }
  | __IDENTIFIER __COLON_COLON __IDENTIFIER  '.' __IDENTIFIER
    {
	$$ = compiler_lookup_type_field( snail_cc, $1, $3, $5 );
    }
  | field_designator '.' __IDENTIFIER
    {
	DNODE *field = $1;
	TNODE *tnode = field ? dnode_type( field ) : NULL;
	$$ = tnode ? tnode_lookup_field( tnode, $3 ) : NULL;
    }
;

constant_expression
  : _NULL
      { $$ = make_const_value( px, VT_NULL ); }

  | __INTEGER_CONST
      {
	  $$ = make_const_value( px, VT_INT, atol( $1 ));
      }

  | __REAL_CONST
      {
	  $$ = make_const_value( px, VT_FLOAT, atof( $1 ));
      }

  | __STRING_CONST
      {
	  $$ = make_const_value( px, VT_STRING, $1 );
      }

  | __IDENTIFIER __IDENTIFIER
      {
	  $$ = make_const_value( px, VT_ENUM, $1, $2 );
      }

  | __IDENTIFIER
      {
	DNODE *const_dnode = snail_lookup_constant( snail_cc, NULL, $1,
						    "constant" );
	$$ = make_zero_const_value();
	if( const_dnode ) {
	    const_value_copy( &$$, dnode_value( const_dnode ), px );
	} else {
	    $$ = make_const_value( px, VT_INT, 0 );
	}
      }

  | __IDENTIFIER __COLON_COLON __IDENTIFIER
      {
	DNODE *const_dnode = snail_lookup_constant( snail_cc, $1, $3,
						    "constant" );
	$$ = make_zero_const_value();
	if( const_dnode ) {
	    const_value_copy( &$$, dnode_value( const_dnode ), px );
	} else {
	    $$ = make_const_value( px, VT_INT, 0 );
	}
      }

  | field_designator '.' __IDENTIFIER
      {
	  $$ = compiler_get_dnode_compile_time_attribute( $1, $3, px );
      }

  | __IDENTIFIER '.' __IDENTIFIER
      {
	  $$ = compiler_make_compile_time_value( snail_cc, NULL, $1, $3, px );
      }

  | __IDENTIFIER __COLON_COLON __IDENTIFIER '.' __IDENTIFIER
      {
	  $$ = compiler_make_compile_time_value( snail_cc, $1, $3, $5, px );
      }

  | '.' __IDENTIFIER
      {
	  $$ = compiler_make_compiler_attribute( $2, px );
      }

  | constant_expression '+' constant_expression
      { $$ = const_value_add( $1, $3 ); }
  | constant_expression '-' constant_expression
      { $$ = const_value_sub( $1, $3 ); }
  | constant_expression '*' constant_expression
      { $$ = const_value_mul( $1, $3 ); }
  | constant_expression '/' constant_expression
      { $$ = const_value_div( $1, $3 ); }
  | '(' constant_expression ')'
      { $$ = $2; }
  | '-' constant_expression %prec __UNARY
      { $$ = const_value_negate( $2 ); }
  ;

%%

static void snail_compile_file( char *filename, cexception_t *ex )
{
    cexception_t inner;

    cexception_guard( inner ) {
        yyin = fopenx( filename, "r", ex );
	if( yyparse() != 0 ) {
	    int errcount = snail_yy_error_number();
	    cexception_raise( &inner, SNAIL_UNRECOVERABLE_ERROR,
			      cxprintf( "compiler could not recover "
					"from errors, quitting now\n"
					"%d error(s) detected\n",
					errcount ));
	} else {
	    int errcount = snail_yy_error_number();
	    if( errcount != 0 ) {
	        cexception_raise( &inner, SNAIL_COMPILATION_ERROR,
				  cxprintf( "%d error(s) detected\n",
					    errcount ));
	    }
	}
    }
    cexception_catch {
        if( yyin ) fclosex( yyin, ex );
	cexception_reraise( inner, ex );
    }
    fclosex( yyin, ex );
}

THRCODE *new_thrcode_from_snail_file( char *filename, char **include_paths,
				      cexception_t *ex )
{
    THRCODE *code;

    assert( !snail_cc );
    snail_cc = new_snail_compiler( filename, include_paths, ex );

    snail_compile_file( filename, ex );

    thrcode_flush_lines( snail_cc->thrcode );
    code = snail_cc->thrcode;
    if( snail_cc->thrcode == snail_cc->function_thrcode ) {
	snail_cc->function_thrcode = NULL;
    } else
    if( snail_cc->thrcode == snail_cc->main_thrcode ) {
	snail_cc->main_thrcode = NULL;
    } else {
	assert( 0 );
    }
    snail_cc->thrcode = NULL;

    thrcode_insert_static_data( code, snail_cc->static_data,
				snail_cc->static_data_size );
    snail_cc->static_data = NULL;
    delete_snail_compiler( snail_cc );
    snail_cc = NULL;

    return code;
}

void snail_printf( cexception_t *ex, char *format, ... )
{
    cexception_t inner;
    va_list ap;

    va_start( ap, format );
    assert( format );
    assert( snail_cc );
    assert( snail_cc->thrcode );

    cexception_guard( inner ) {
	thrcode_printf_va( snail_cc->thrcode, &inner, format, ap );
    }
    cexception_catch {
	va_end( ap );
	cexception_reraise( inner, ex );
    }
    va_end( ap );
}

static int errcount = 0;

int snail_yy_error_number( void )
{
    return errcount;
}

void snail_yy_reset_error_count( void )
{
    errcount = 0;
}

int yyerror( char *message )
{
    extern char *progname;
    /* if( YYRECOVERING ) return; */
    errcount++;
    fflush(NULL);
    if( strcmp( message, "syntax error" ) == 0 ) {
	message = "incorrect syntax";
    }
    fprintf(stderr, "%s: %s(%d,%d): ERROR, %s\n", 
	    progname, snail_cc->filename,
	    snail_flex_current_line_number(),
	    snail_flex_current_position(),
	    message );
    fprintf(stderr, "%s\n", snail_flex_current_line() );
    fprintf(stderr, "%*s\n", snail_flex_current_position(), "^" );
    fflush(NULL);
    return 0;
}

int yywrap()
{
    if( snail_cc->include_files ) {
	compiler_close_include_file( snail_cc, px );
	return 0;
    } else {
	return 1;
    }
}

void snail_yy_debug_on( void )
{
#ifdef YYDEBUG
    yydebug = 1;
#endif
}

void snail_yy_debug_off( void )
{
#ifdef YYDEBUG
    yydebug = 0;
#endif
}
