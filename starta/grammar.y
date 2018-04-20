/*-------------------------------------------------------------------------*\
* $Author$
* $Date$ 
* $Revision$
* $URL$
\*-------------------------------------------------------------------------*/

%{
/* exports: */
#include <grammar_y.h>

/* uses: */
#include <stdio.h>
#include <stdarg.h>
#include <limits.h>
#include <string.h>
#include <ctype.h>
#include <dlfcn.h>
#include <dirent.h> /* For scanning directories (recursively) */
#include <fcntl.h> /* Definition of AT_* constants */
#include <sys/stat.h> /* For calling 'fstatat()' -- 'struct stat' definition */
#include <errno.h>
#include <common.h>
#include <cexceptions.h>
#include <cxprintf.h>
#include <allocx.h>
#include <stringx.h>
#include <strpool.h>
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
#include <tnode_compat.h>
#include <strpool.h>
#include <bytecode_file.h> /* for bytecode_file_hdr_t, needed by
			      compiler_native_type_size() */
#include <cvalue_t.h>
#include <lexer_flex.h>
#include <yy.h>
#include <alloccell.h>
#include <implementation.h>
#include <assert.h>

char *progname;

static char *compiler_version = "0.0";

static unsigned char memleak_debug;
 
/* COMPILER_STATE contains necessary compiler state that must be
   saved and restored when include files are processed. */

typedef struct COMPILER_STATE {
    char *filename;
    char *use_module_name;
    char *module_filename;
    DNODE *requested_module_dnode;
    FILE *yyin;
    ssize_t line_no;
    ssize_t column_no;
    char **include_paths;
    struct COMPILER_STATE *next;
} COMPILER_STATE;

static void delete_compiler_state( COMPILER_STATE *state )
{
    if( state ) {
	freex( state );
    }
}

static ssize_t string_count( char **strings )
{
    ssize_t len = 0;

    if( strings )
      while( strings[len] )
	len ++;

    return len;
}

static char** clone_string_array( char **str_array, cexception_t *ex )
{
    char ** volatile cloned;
    ssize_t array_length = string_count( str_array );
    cexception_t inner;
    ssize_t i;

    if( !str_array ) return NULL;

    cloned = callocx( sizeof(cloned[0]), array_length + 1, ex );
    cexception_guard( inner ) {
        for( i = 0; i < array_length; i ++ ) {
            cloned[i] = strdupx( str_array[i], &inner );
        }
    }
    cexception_catch {
        for( i = 0; i < array_length; i ++ ) {
            if( cloned[i] )
                freex( cloned[i] );
        }
        freex( cloned );
        cexception_reraise( inner, ex );
    }
    return cloned;
}

static COMPILER_STATE *new_compiler_state( char *filename,
					   char *use_module_name,
					   char *module_filename,
                                           DNODE *requested_module,
					   FILE *file,
					   ssize_t line_no,
					   ssize_t column_no,
                                           char **include_paths,
					   COMPILER_STATE *next,
					   cexception_t *ex )
{
    cexception_t inner;
    COMPILER_STATE * volatile state = callocx( sizeof( *state ), 1, ex );

    cexception_guard( inner ) {
        state->include_paths = clone_string_array( include_paths, &inner );
    }
    cexception_catch {
        freex( state );
        cexception_reraise( inner, ex );
    }

    state->filename = filename;
    state->use_module_name = use_module_name;
    state->module_filename = module_filename;
    state->requested_module_dnode = requested_module;
    state->yyin = file;
    state->line_no = line_no;
    state->column_no = column_no;
    state->next = next;

    return state;
}

#define starting_local_offset -1

typedef struct {
    /* Threaded code (bytecode) that is generated: */
    THRCODE *thrcode;
    THRCODE *main_thrcode;
    THRCODE *function_thrcode;

    THRLIST *thrstack; /* a stack to push generated thrcode bodies
                          when generating nested control
                          structures. */

    char *static_data;
    ssize_t static_data_size;
    VARTAB *vartab;   /* declared variables, with scopes */
    VARTAB *consts;   /* declared constants, with scopes */
    TYPETAB *typetab; /* declared types and their scopes */
    VARTAB *operators; /* operators declared outside of type definitions */

    STLIST *symtab_stack; /* pushed symbol tables */

    ssize_t local_offset;
    ssize_t *local_offset_stack;
    int local_offset_stack_size;

    int last_interface_number;

    /* the addr_stack is an array-used-as-stack and holds entry
       addresses of the loops that are currently being compiled. */
    int addr_stack_size;
    ssize_t *addr_stack;

    /* Paths to search for included files, modules, and libraries: */
    char **include_paths;

    /* The following fields are used to process include files and
       modules: */
    char *filename;
    FILE *yyin;
    char *use_module_name;
    char *module_filename;
    DNODE *requested_module;
    COMPILER_STATE *include_files;

    DNODE *current_function; /* Function that is currently being
				compiled. NOTE! this field must not be
				deleted in delete_compiler() */

    DLIST *current_function_stack;

    TNODE *current_type;

    TLIST *current_type_stack;

    DNODE *current_call;     /* function call that is currently
				being processed. */
    DLIST *current_call_stack;

    ssize_t current_interface_nr;
    ssize_t *current_interface_nr_stack;
    int current_interface_nr_stack_size;

    DNODE *current_arg;        /* formal function argument that is currently
				  being processed. NOTE! this field
				  must not be deleted in delete_compiler() */
    DLIST *current_arg_stack;

    /* The enodes in the e_stack mimick the evaluation stack of an
       expression or statement under compilation and hold types of all
       intermediate values. First enode in the list is the top of the
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
    DLIST *loop_stack;

    /* number sequentially all exceptions declared in each module or
       in the main program: */
    int latest_exception_nr;

    /* the following variables describe nesting try{} blocks */
    int try_block_level;
    ssize_t *try_variable_stack;

    /* catch and switch jumpover stack */
    ssize_t catch_jumpover_nr;
    ssize_t *catch_jumpover_stack;
    int catch_jumpover_stack_length;

    /* fields used for the implementation of modules: */
    VARTAB *compiled_modules;
    DLIST *current_module_stack;
    DNODE *current_module; /* this field must not be deleted when deleting
			       COMPILER */

    /* track which non-null reference fields of a structure are
       initialised: */
    VARTAB *initialised_references;
    STLIST *initialised_ref_symtab_stack;

    /* String pool from which the lexer will allocate strings and put
       their pool indexes in the Yacc stack: */
    STRPOOL *strpool;

} COMPILER;

static void delete_string_array( char ***array )
{
    assert( array );

    if( *array ) {
        ssize_t i;
        for( i = 0; (*array)[i]; i++ ) {
            freex( (*array)[i] );
        }
        freex( *array );
    }
    *array = NULL;
}

static void compiler_drop_include_file( COMPILER *c );

static void delete_compiler( COMPILER *c )
{
    if( c ) {
	while( c->include_files ) {
	    compiler_drop_include_file( c );
	}
	freex( c->filename );
	if( c->yyin ) fclosex( c->yyin, NULL );

        delete_thrcode( c->thrcode );
        delete_thrcode( c->main_thrcode );
        delete_thrcode( c->function_thrcode );

        delete_thrlist( c->thrstack );

	freex( c->static_data );
        vartab_break_cycles( c->vartab );
        vartab_break_cycles( c->consts );
        vartab_break_cycles( c->compiled_modules );
        vartab_break_cycles( c->operators );
        typetab_break_cycles( c->typetab );

	delete_vartab( c->vartab );
	delete_vartab( c->consts );
	delete_vartab( c->compiled_modules );
	delete_typetab( c->typetab );
	delete_vartab( c->operators );

	delete_stlist( c->symtab_stack );

	delete_dnode( c->bytecode_labels );
	delete_fixup_list( c->bytecode_fixups );

	delete_dnode( c->loops );
        delete_dlist( c->loop_stack );

        freex( c->local_offset_stack );
	freex( c->addr_stack );
	delete_elist( c->saved_estacks );
	delete_enode( c->e_stack );
        freex( c->try_variable_stack );

        dnode_break_cycles( c->current_call );
	delete_dnode( c->current_call );

        dlist_break_cycles( c->current_call_stack );
	delete_dlist( c->current_call_stack );
        assert( !c->current_arg_stack );
        freex( c->current_interface_nr_stack );

	delete_dlist( c->current_module_stack );

        dnode_break_cycles( c->current_module );
        delete_dnode( c->current_module );

        vartab_break_cycles( c->initialised_references );
        delete_vartab( c->initialised_references );
	delete_stlist( c->initialised_ref_symtab_stack );

        dlist_break_cycles( c->current_function_stack );
        delete_dlist( c->current_function_stack );

        tlist_break_cycles( c->current_type_stack );
        delete_tlist( c->current_type_stack );

        tnode_break_cycles( c->current_type );
        delete_tnode( c->current_type );

        freex( c->use_module_name );
        freex( c->module_filename );

        dnode_break_cycles( c->requested_module );
        delete_dnode( c->requested_module );

        delete_string_array( &c->include_paths );

        if( memleak_debug ) {
            strpool_print_strings_to_stderr( c->strpool );
            dnode_print_allocated_to_stderr();
            tnode_print_allocated_to_stderr();
        }

        delete_strpool( c->strpool );
        
        freex( c );
    }
}

static COMPILER *new_compiler( char *filename,
                               char **include_paths,
                               cexception_t *ex )
{
    cexception_t inner;
    COMPILER *cc = callocx( 1, sizeof(COMPILER), ex );

    cexception_guard( inner ) {
        if( filename && !(strcmp( filename, "-" ) == 0) ) {
            cc->filename = strdupx( filename, &inner );
        } else {
            cc->filename = strdupx( "-", &inner );
        }
        cc->main_thrcode = new_thrcode( &inner );
        cc->function_thrcode = new_thrcode( &inner );

	/* cc->thrcode = cc->function_thrcode; */
	cc->thrcode = NULL;

	thrcode_set_immediate_printout( cc->function_thrcode, 1 );

	cc->vartab = new_vartab( &inner );
	cc->consts = new_vartab( &inner );
	cc->compiled_modules = new_vartab( &inner );
	cc->typetab = new_typetab( &inner );
	cc->operators = new_vartab( &inner );

	cc->local_offset = starting_local_offset;

	cc->include_paths = include_paths;

        cc->strpool = new_strpool( &inner );
    }
    cexception_catch {
        delete_compiler( cc );
        cexception_reraise( inner, ex );
    }
    return cc;
}

static void compiler_save_flex_stream( COMPILER *c, char *filename,
				       cexception_t *ex  )
{
    assert( !c->filename );
    c->filename = strdupx( filename, ex );
    c->yyin = yyin = fopenx( filename, "r", ex );

    compiler_flex_push_state( yyin, ex );
    compiler_flex_set_current_line_number( 1 );
    compiler_flex_set_current_position( 1 );
}

static void compiler_restore_flex_stream( COMPILER *c )
{
    COMPILER_STATE *top;

    top = c->include_files;
    assert( top );

    if( c->yyin ) fclose( c->yyin );
    c->yyin = yyin = top->yyin;
    freex( c->filename );
    c->filename = NULL;

    compiler_flex_set_current_line_number( top->line_no );
    compiler_flex_set_current_position( top->column_no );
    compiler_flex_pop_state();
}

static void compiler_push_compiler_state( COMPILER *c,
					  cexception_t *ex )
{
    COMPILER_STATE *cstate;

    cstate = new_compiler_state( c->filename, c->use_module_name, 
                                 c->module_filename, c->requested_module,
                                 c->yyin,
				 compiler_flex_current_line_number(),
				 compiler_flex_current_position(),
                                 c->include_paths,
				 c->include_files, ex );

    c->filename = NULL;
    c->use_module_name = NULL;
    c->module_filename = NULL;
    c->requested_module = NULL;
    c->include_files = cstate;
}

void compiler_pop_compiler_state( COMPILER *c )
{
    COMPILER_STATE *top;

    top = c->include_files;
    assert( top );

    freex( c->use_module_name );
    c->use_module_name = top->use_module_name;

    freex( c->module_filename );
    c->module_filename = top->module_filename;

    delete_dnode( c->requested_module );
    c->requested_module = top->requested_module_dnode;

    c->include_files = top->next;
    assert( !c->filename );
    c->filename = top->filename;

    delete_string_array( &c->include_paths );
    c->include_paths = top->include_paths;

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
	freex( full_path );
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
        } else if( path ) {
            n = snprintf( full_path, full_path_size, "%s/%s",
                          path, filename );
        } else {
            n = snprintf( full_path, full_path_size, "%s",
                          filename );
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

/*
 * Recursively open directories and scan their contents:
 */
static int rscandir( DIR *dp, char *filename,
                     char *dirname,  /* Basename of the currently
                                        processed directory */
                     char *volatile* dirpath, /* Full path to the
                                                 currently processed
                                                 directory */
                     cexception_t *ex )
{
    struct dirent *dire;

    assert( dirpath );

    while( (dire = readdir( dp )) != NULL ) {
        struct stat fstat;
        if( fstatat( dirfd(dp), dire->d_name, &fstat, /* flags = */ 0 ) != 0 ) {
            yyerrorf( "%s: ERROR, could not stat (fstatat) entry '%s' - %s\n",
                      filename, dire->d_name, strerror(errno));
            errno = 0;
            continue;                
        }
        if( strcmp( filename, dire->d_name ) == 0 ) {
            /* printf( ">>> found '%s' in '%s'\n", filename, dirname ); */
            assert( !*dirpath );
            *dirpath = strdupx( dirname, ex );
            return 1;
        }
#if 0
        printf( "inode = %8jd, offset = %10jd, length = %d, type = %d, "
                "is_dir = %d, name = '%s'\n", (intmax_t)dire->d_ino,
                (intmax_t)dire->d_off, dire->d_reclen,
                dire->d_type, S_ISDIR(fstat.st_mode), dire->d_name );
#endif
        if( S_ISDIR(fstat.st_mode) &&
            strcmp( dire->d_name, "." ) != 0 &&
            strcmp( dire->d_name, ".." ) != 0 ) {
            int subdir_fd;
            DIR *subdir_dp;
            if( (subdir_fd =
                 openat( dirfd(dp), dire->d_name, O_RDONLY )) < 0 ) {
                yyerrorf( "%s: ERROR, could not open subdirectory "
                          "'%s' - %s\n", filename, dire->d_name,
                          strerror(errno));
                errno = 0;
                continue;
            }
            if( (subdir_dp = fdopendir( subdir_fd )) == NULL ) {
                yyerrorf( "%s: ERROR, could not fd-open subdirectory "
                          "'%s' - %s\n", filename, dire->d_name,
                          strerror(errno));
                errno = 0;
                continue;
            }
            int is_found = 
                rscandir( subdir_dp, filename, dire->d_name, dirpath, ex );
            closedir( subdir_dp );
            if( is_found ) {
                assert( *dirpath );
                char *new_dirpath = NULL;
                ssize_t new_length =
                    strlen( *dirpath ) + 
                    strlen( dirname ) + 
                    2; /* Two positions extra for '/' and for '\0'. */
                int remove = 0; /* number of characters to remove from
                                   the directory name end */
                if( strstr( dirname, "//" ) == 
                    dirname + strlen(dirname) - 2 ) {
                    remove = 2;
                } else if( strstr( dirname, "/" ) ==
                           dirname + strlen(dirname) - 1 ) {
                    remove = 1;
                }
                new_dirpath = mallocx( new_length, ex );
                strncpy( new_dirpath, dirname, strlen(dirname) - remove );
                new_dirpath[strlen(dirname) - remove]  = '\0';
                strcat( new_dirpath, "/" );
                strcat( new_dirpath, *dirpath );
                freex( *dirpath );
                *dirpath = new_dirpath;
                return 1;
            }
        }
        errno = 0;
    }
    if( errno != 0 ) {
        yyerrorf( "%s: ERROR, could not read directory - "
                  "%s\n", filename, strerror(errno));
    }
    return 0;
}

/*
  A simplified path will not contain multiple '/' characters, and will
  not contain substrings "./". E.g.:

  Original path:                   Simplified path:
  "./././this///is/a////path//" -> "this/is/a/path/"
*/

static char *simplify_path( char *path, cexception_t *ex )
{
    char *spath = strdupx( path, ex ); /* Simplified path */

    /* Remove duplicated '/' occurences: */
    char *src, *dst;
    src = dst = spath;
    while( *src ) {
        *dst++ = *src;
        if( *src == '/' ) {
            /* Skip repeated '/' occurences: */
            while( *src == '/' ) src++;
        } else {
            /* otherwise, move to the next character: */
            src ++;
        }
    }
    *dst = '\0';

    /* Remove './' occurences: */
    src = dst = spath;
    while( *src ) {
        if( src[0] == '.' && src[1] == '/' ) {
            /* Skip the "./" construct: */
            src += 2;
            continue;
        }
        if( *src == '.' ) {
            /* Copy '..' directory names: */
            while( *src == '.' ) {
                *dst ++ = *src ++;
            }
        } else {
            /* Copy any other characters as they are: */
            *dst++ = *src++;
        }
    }
    *dst = '\0';
    return spath;
}

static char *interpolate_string( char *path, char *filename,
                                 cexception_t *ex )
{
    char * volatile interpolated = NULL;
    char * volatile newint = NULL;
    ssize_t intsize = 0;
    char *pos = index( path, '$' );
    cexception_t inner;
    
    interpolated = strdupx( path, ex );
    intsize = strlen( interpolated + 1 );

    cexception_guard( inner ) {
        while( pos != NULL ) {
            if( pos[1] == 'D' || pos[1] == 'P' ) {
                char *dirend = rindex( filename, '/' );
                char *dirname;
                if( dirend != NULL ) {
                    if( dirend == filename && *dirend == '/' ) {
                        dirname = "/";
                        dirend = dirname + 1;
                    } else {
                        dirname = filename;
                    }
                } else {
                    dirname = ".";
                    dirend = dirname + 1;
                }

#if 0
                printf( ">>> $D = '%s' till '%s'\n", dirname, dirend );
#endif
                if( pos[1] == 'P' ) {
                    char *dirnow = dirname;
                    if( dirend > dirnow ) dirend--;
                    while( dirend > dirnow && *dirend != '/' ) {
                        dirend --;
                    }
                    if( dirend == dirnow ) {
                        if( *dirnow == '/' ) {
                            dirname = "/";
                            dirend = dirname + 1;
                        } else if( *dirnow == '.' && dirnow[1] == '.' ) {
                            dirname = "../..";
                            dirend = dirname + 5;
                        } else if( *dirnow == '.' && dirnow[1] == '\0' ) {
                            dirname = "..";
                            dirend = dirname + 2;
                        } else {
                            dirname = ".";
                            dirend = dirname + 1;
                        }
                    }
#if 0
                    printf( ">>> $P = '%s' till '%s'\n", dirname, dirend );
#endif
                }

                ssize_t dirlen = dirend - dirname;
                intsize += dirlen;
                newint = mallocx( dirlen + strlen(interpolated) + 1, &inner );
                strncpy( newint, interpolated, pos - path );
                strncpy( newint + (pos - path), dirname, dirlen );
                strncpy( newint + (pos - path) + dirlen,
                         pos + 2, strlen(interpolated) - (pos+2-path) + 1 );
                freex( interpolated );
                interpolated = newint;
                newint = NULL;
            }
            pos = index( pos+1, '$' );
        } 
    }
    cexception_catch {
        freex( interpolated );
        freex( newint );
        cexception_reraise( inner, ex );
    }

    return interpolated;
}

static char *compiler_find_include_file( COMPILER *c, char *filename,
					 cexception_t *ex )
{
    char **path;
    char *full_path;
    char *version = compiler_version;
    char *dollar;

    assert( c );

    if( !filename ) {
	return make_full_file_name( NULL, NULL, NULL, ex );
    }

    if( filename && filename[0] == '/' ) {
        /* we have an absolute path -- no search or interpolation is
           necessary: */
        return filename;
    }

    /* If a provided 'filename' contains $D and $P directory names,
       lets interpoate the script directory or script parent directory
       insted of them: */
    if( (dollar = strchr( filename, '$' )) != NULL && 
        (dollar[1] == 'D' || dollar[1] == 'P') ) {
        cexception_t inner;
        char *volatile spath = simplify_path( c->filename, ex );
        char *volatile interpolated = NULL;
        char *volatile full_name = NULL;
        cexception_guard( inner ) {
            interpolated = interpolate_string( filename, spath, &inner );
            /* printf( ">>> %s\n", interpolated ); */
            full_name =  make_full_file_name( interpolated /*filename*/,
                                              NULL /*path*/, NULL /*version*/,
                                              &inner );
            freex( interpolated );
            freex( spath );
            return full_name;
        }
        cexception_catch {
            freex( interpolated );
            freex( spath );
            cexception_reraise( inner, ex );
        }
    }

    if( !c->include_paths ) {
	return filename;
    } else {
	for( path = c->include_paths; *path != NULL; path ++ ) {
	    FILE *f;
            /* first, check a compiler version-specific library: */
	    full_path = make_full_file_name( filename, *path, version, ex );
            /* printf( ">>> Checking '%s'\n", full_path ); */
	    f = fopen( full_path, "r" );
	    if( f ) {
		fclose( f );
		/* printf( "Found '%s'\n", full_path ); */
		return full_path;
	    }
            /* if no luck, check for a generic library: */
	    full_path = make_full_file_name( filename, *path, NULL, ex );
            /* printf( ">>> Checking '%s'\n", full_path ); */
	    f = fopen( full_path, "r" );
	    if( f ) {
		fclose( f );
		/* printf( "Found '%s'\n", full_path ); */
		return full_path;
	    }
            if( strstr( *path, "//" ) == 
                *path + strlen(*path) - 2 ) {
                /* printf( ">>>> will search '%s' recursively\n", *path ); */
                cexception_t inner;
                char * volatile dirpath = NULL;
                DIR * volatile dp = opendir( *path );
                int volatile is_found = 0;

                if( !dp ) {
                    fprintf( stderr, "%s: ERROR, could not open directory - %s\n",
                             *path, strerror(errno));
                    continue;
                }
                cexception_guard( inner ) {
                    is_found = 
                        rscandir( dp, filename, *path, &dirpath, &inner );
                    closedir( dp );
                    dp = NULL;
                    if( is_found ) {
                        full_path = make_full_file_name( filename, dirpath, 
                                                         NULL, &inner );
                        /* printf( ">>>> The found path is '%s'\n",
                           full_path ); */
                    }
                    freex( dirpath );
                }
                cexception_catch {
                    freex( dirpath );
                    closedir( dp );
                    cexception_reraise( inner, ex );
                }
                if( is_found )
                    return full_path;
            }
	}
	make_full_file_name( NULL, NULL, NULL, ex );
	return NULL;
    }
}

static void compiler_open_include_file( COMPILER *c, char *filename,
					cexception_t *ex )
{
    char *full_name = compiler_find_include_file( c, filename, ex );
    if( !full_name ) {
        yyerrorf( "could not find module '%s' in the include path",
                  filename );
        cexception_raise
            ( ex, COMPILER_FILE_SEARCH_ERROR,
              "could not find required module, terminating" );
    } else {
        compiler_push_compiler_state( c, ex );
        compiler_save_flex_stream( c, full_name, ex );
    }
}

static void compiler_push_symbol_tables( COMPILER *c,
					 cexception_t *ex )
{
    SYMTAB *symtab = new_symtab( c->vartab, c->consts, c->typetab,
                                 c->operators, ex );
    stlist_push_symtab( &c->symtab_stack, &symtab, ex );

    c->vartab = new_vartab( ex );
    c->consts = new_vartab( ex );
    c->typetab = new_typetab( ex );
    c->operators = new_vartab( ex );
}

static void compiler_use_exported_module_names( COMPILER *c,
                                                DNODE *module,
                                                cexception_t *ex )
{
    assert( module );

    /* printf( "importing module '%s'\n", dnode_name( module )); */

    vartab_copy_table( c->vartab, dnode_vartab( module ), ex );
    vartab_copy_table( c->consts, dnode_constants_vartab( module ), ex );
    typetab_copy_table( c->typetab, dnode_typetab( module ), ex );
    vartab_copy_table( c->operators, dnode_operator_vartab( module ), ex );
}

static void compiler_pop_symbol_tables( COMPILER *c )
{
    SYMTAB *symtab = stlist_pop_data( &c->symtab_stack );

    if( symtab ) {
	delete_vartab( c->vartab );
	delete_vartab( c->consts );
	delete_typetab( c->typetab );
	delete_vartab( c->operators );

	obtain_tables_from_symtab( symtab, &c->vartab, &c->consts,
				   &c->typetab, &c->operators );

	delete_symtab( symtab );
    }
}

static void compiler_push_initialised_ref_tables( COMPILER *c,
                                                  cexception_t *ex )
{
    SYMTAB *symtab = new_symtab( c->initialised_references, NULL, NULL, NULL, ex );
    stlist_push_symtab( &c->initialised_ref_symtab_stack, &symtab, ex );

    c->initialised_references = new_vartab( ex );
}

static void compiler_pop_initialised_ref_tables( COMPILER *c )
{
    SYMTAB *symtab = stlist_pop_data( &c->initialised_ref_symtab_stack );
    VARTAB *dummy_v = NULL;
    TYPETAB *dummy_t = NULL;
    VARTAB *dummy_o = NULL;

    delete_vartab( c->initialised_references );
    c->initialised_references = NULL;

    if( symtab ) {
	obtain_tables_from_symtab( symtab, &c->initialised_references,
                                   &dummy_v, &dummy_t, &dummy_o );
	delete_symtab( symtab );
    }
}

static void compiler_drop_include_file( COMPILER *c )
{
    compiler_restore_flex_stream( c );
    compiler_pop_compiler_state( c );
}

static void compiler_close_include_file( COMPILER *c,
					 cexception_t *ex )
{
    if( c->use_module_name ) {
	DNODE *module = NULL;
	module = vartab_lookup_silently( c->compiled_modules,
                                         c->use_module_name,
                                         /* count = */ NULL,
                                         /* is_imported = */ NULL );
	if( module ) {
	    compiler_use_exported_module_names( c, module, ex );
	} else {
	    yyerrorf( "no module named '%s'?", c->use_module_name );
	}
    }

    if( c->requested_module ) {
        cexception_t inner;
        char *synonim;
        if( (synonim = dnode_synonim( c->requested_module )) != NULL ) {
            TYPETAB * typetab = NULL;
            VARTAB * vartab = NULL;
            VARTAB * consttab = NULL;
            VARTAB * optab = NULL;

            SYMTAB * volatile symtab = NULL;

            cexception_guard( inner ) {
                symtab = new_symtab( c->vartab, c->consts, c->typetab,
                                     c->operators, &inner );

                DNODE *compiled_module =
                    vartab_lookup_module( c->vartab, c->requested_module,
                                          symtab );
                /* Synonim is inserted as a simple variable, not as a
                   module (i.e. only the name uniqueness is
                   considered, module arguments are not taken into
                   account). This is necessary to ensure unique names
                   for renamed parametrised modules, as in 'use M(int)
                   as M1; use M(long) as M2' */
                if( compiled_module ) {
                    share_dnode( compiled_module );
                    vartab_insert( c->vartab, synonim,
                                   &compiled_module, &inner );
                }

                obtain_tables_from_symtab( symtab, &vartab,
                                           &consttab, &typetab, &optab );
                delete_symtab( symtab );
            }
            cexception_catch {
                obtain_tables_from_symtab( symtab, &vartab,
                                           &consttab, &typetab, &optab );
                delete_symtab( symtab );
                cexception_reraise( inner, ex );
            }            
        }
    }

    compiler_restore_flex_stream( c );
    compiler_pop_compiler_state( c );
    freex( c->module_filename ); /* CHECKME: does this work with files
                                     included from include files?
                                     S.G. */
    c->module_filename = NULL;
}

static void push_ssize_t( ssize_t **array, int *size, ssize_t value,
                          cexception_t *ex )
{
    *array = reallocx( *array, ( *size + 1 ) * sizeof(**array), ex );
    (*array)[*size] = value;
    (*size) ++;
}

static ssize_t pop_ssize_t( ssize_t **array, int *size, cexception_t *ex )
{
    assert( size );
    assert( *size > 0 );
    (*size) --;
    return (*array)[*size];
}

static void compiler_push_current_address( COMPILER *c, cexception_t *ex )
{
    push_ssize_t( &c->addr_stack, &c->addr_stack_size,
		  thrcode_length(c->thrcode), ex );
}

static ssize_t compiler_pop_address( COMPILER *c, cexception_t *ex )
{
    return pop_ssize_t( &c->addr_stack, &c->addr_stack_size, ex );
}

static ssize_t compiler_pop_offset( COMPILER *c, cexception_t *ex )
{
    return pop_ssize_t( &c->addr_stack, &c->addr_stack_size, ex )
           - thrcode_length( c->thrcode );
}

static ssize_t compiler_code_length( COMPILER *c )
{
    return thrcode_length( c->thrcode );
}

static void compiler_push_relative_fixup( COMPILER *c, cexception_t *ex )
{
    thrcode_push_relative_fixup_here( c->thrcode, "", ex );
}

static void compiler_push_absolute_fixup( COMPILER *c, cexception_t *ex )
{
    thrcode_push_absolute_fixup_here( c->thrcode, "", ex );
}

static void compiler_fixup_here( COMPILER *c )
{
    thrcode_internal_fixup_here( c->thrcode );
}

static void compiler_fixup( COMPILER *c, ssize_t value )
{
    thrcode_internal_fixup( c->thrcode, value );
}

static void compiler_swap_fixups( COMPILER *c )
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

static TNODE *compiler_typetab_insert_msg( COMPILER *cc,
                                           char *name,
                                           type_suffix_t suffix_type,
                                           TNODE *volatile *tnode,
                                           char *type_conflict_msg,
                                           cexception_t *ex )
{
    assert( tnode );
    TNODE *volatile lookup_node = NULL;
    int count = 0;
    int is_imported = 0;
    TNODE *volatile shared_tnode = share_tnode( *tnode );
    cexception_t inner;

    cexception_guard( inner ) {
        lookup_node =
            typetab_insert_suffix( cc->typetab, name, suffix_type,
                                   &shared_tnode,
                                   &count, &is_imported, &inner );
        assert( !shared_tnode );
    }
    cexception_catch {
        delete_tnode( shared_tnode );
        cexception_reraise( inner, ex );
    }

    if( lookup_node != *tnode ) {
	if( tnode_is_forward( lookup_node )) {
            if( tnode_is_non_null_reference( *tnode ) !=
                tnode_is_non_null_reference( lookup_node )) {
                yyerrorf( "redeclaration of forward type '%s' changes "
                          "non-null flag", tnode_name( lookup_node ) );
            }
	    tnode_shallow_copy( lookup_node, *tnode );
	} else if( tnode_is_extendable_enum( lookup_node )) {
	    tnode_merge_field_lists( lookup_node, *tnode );
	    compiler_check_enum_basetypes( lookup_node, *tnode );
	} else if( !is_imported ) {
	    char *name = tnode_name( *tnode );
	    if( strstr( type_conflict_msg, "%s" ) != NULL ) {
		yyerrorf( type_conflict_msg, name );
	    } else {
		yyerrorf( type_conflict_msg );
	    }
	}
    }
    dispose_tnode( tnode );
    return lookup_node;
}

static int compiler_current_scope( COMPILER *cc )
{
    return vartab_current_scope( cc->vartab );
}

static void compiler_typetab_insert( COMPILER *cc,
                                     TNODE *volatile *tnode,
                                     cexception_t *ex )
{
    assert( tnode );

    TNODE *volatile lookup_tnode =
        compiler_typetab_insert_msg( cc, tnode_name( *tnode ),
                                     TS_NOT_A_SUFFIX, tnode,
                                     "type '%s' is already declared", ex );

    if( cc->current_module &&
        compiler_current_scope( cc )  == 0 ) {
        TNODE *volatile shared_tnode = share_tnode( lookup_tnode );

        cexception_t inner;
        cexception_guard( inner ) {
            dnode_typetab_insert_named_tnode( cc->current_module,
                                              shared_tnode, &inner );
            shared_tnode = NULL;
        }
        cexception_catch {
            delete_tnode( shared_tnode );
            cexception_reraise( inner, ex );
        }
    } 
}

static void compiler_vartab_insert_named_vars( COMPILER *cc,
                                               DNODE *volatile *vars,
                                               cexception_t *ex )
{
    assert( vars );
    DNODE *volatile shared_vars = share_dnode( *vars );

    cexception_t inner;
    cexception_guard( inner ) {
        vartab_insert_named_vars( cc->vartab, vars, &inner );
        if( cc->current_module && dnode_scope( shared_vars ) == 0 ) {
            dnode_vartab_insert_named_vars( cc->current_module,
                                            &shared_vars, &inner );
        } else {
            delete_dnode( shared_vars );
        }
    }
    cexception_catch {
        delete_dnode( shared_vars );
        cexception_reraise( inner, ex );
    }
}

static void compiler_vartab_insert_single_named_var( COMPILER *cc,
                                                     DNODE *volatile *var,
                                                     cexception_t *ex )
{
    assert( var );
    DNODE *volatile shared_var = share_dnode( *var );
    char *name = dnode_name( *var );
    cexception_t inner;
    
    assert( name );
    cexception_guard( inner ) {
        vartab_insert( cc->vartab, name, var, &inner );
        if( cc->current_module && dnode_scope( shared_var ) == 0 ) {
            dnode_vartab_insert_dnode( cc->current_module, name,
                                       &shared_var, &inner );
        } else {
            delete_dnode( shared_var );
        }
    }
    cexception_catch {
        delete_dnode( shared_var );
        cexception_reraise( inner, ex );
    }
}

static void compiler_consttab_insert_consts( COMPILER *cc,
                                             DNODE *volatile *consts,
                                             cexception_t *ex )
{
    assert( consts );
    DNODE *volatile shared_consts = share_dnode( *consts );
    cexception_t inner;

    cexception_guard( inner ) {
        vartab_insert_named_vars( cc->consts, consts, &inner );
        if( cc->current_module ) {
            dnode_consttab_insert_consts( cc->current_module,
                                          &shared_consts, &inner );
        } else {
            delete_dnode( shared_consts );
        }
    }
    cexception_catch {
        delete_dnode( shared_consts );
        cexception_reraise( inner, ex );
    }
}

static void compiler_insert_tnode_into_suffix_list( COMPILER *cc,
                                                    TNODE *tnode,
                                                    cexception_t *ex )
{
    TNODE *base_type = NULL;
    char *suffix;
    type_kind_t type_kind;
    char *type_conflict_msg = NULL;
    TNODE *volatile shared_tnode = NULL;

    suffix = tnode_suffix( tnode );
    if( !suffix ) suffix = "";

    type_kind = tnode_kind( tnode );

    if( type_kind == TK_DERIVED &&
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
	shared_tnode = share_tnode( tnode );
	compiler_typetab_insert_msg( cc, suffix, TS_INTEGER_SUFFIX,
                                     &shared_tnode,
                                     type_conflict_msg, ex );
	if( cc->current_module ) {
            shared_tnode = share_tnode( tnode );
	    dnode_typetab_insert_tnode_suffix( cc->current_module, suffix,
					       TS_INTEGER_SUFFIX,
					       shared_tnode, ex );
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
	shared_tnode = share_tnode( tnode );
	compiler_typetab_insert_msg( cc, suffix, TS_FLOAT_SUFFIX,
                                     &shared_tnode,
                                     type_conflict_msg, ex );
	if( cc->current_module ) {
            shared_tnode = share_tnode( tnode );
	    dnode_typetab_insert_tnode_suffix( cc->current_module, suffix,
					       TS_FLOAT_SUFFIX,
					       shared_tnode, ex );
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
	shared_tnode = share_tnode( tnode );
	compiler_typetab_insert_msg( cc, suffix, TS_STRING_SUFFIX,
                                     &shared_tnode,
                                     type_conflict_msg, ex );
	if( cc->current_module ) {
            shared_tnode = share_tnode( tnode );
	    dnode_typetab_insert_tnode_suffix( cc->current_module, suffix,
					       TS_STRING_SUFFIX,
					       shared_tnode, ex );
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
	shared_tnode = share_tnode( tnode );
	compiler_typetab_insert_msg( cc, suffix, TS_NOT_A_SUFFIX,
                                     &shared_tnode,
                                     type_conflict_msg, ex );
	if( cc->current_module ) {
            shared_tnode = share_tnode( tnode );
	    dnode_typetab_insert_tnode_suffix( cc->current_module, suffix,
					       TS_NOT_A_SUFFIX,
					       shared_tnode, ex );
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
    case TK_DERIVED:
        delete_tnode( tnode );
	break;
    default:
	yyerrorf( "types of kind '%s' do not have suffix table",
		  tnode_kind_name( tnode ));
	break;
    }
}

static void compiler_push_current_type( COMPILER *c,
                                        TNODE * volatile *type_tnode,
                                        cexception_t *ex )
{
    assert( type_tnode );
    tlist_push_tnode( &c->current_type_stack,
                      &c->current_type, ex );
    c->current_type = *type_tnode;
    *type_tnode = NULL;
}

static TNODE *compiler_pop_current_type( COMPILER *c )
{
    TNODE *old_tnode = c->current_type;
    c->current_type = tlist_pop_data( &c->current_type_stack );
    return old_tnode;
}

/* Push expression with a given type on the expression trace stack: */

static void compiler_push_typed_expression( COMPILER *c, TNODE *tnode,
                                            cexception_t *ex )
{
    ENODE *expr_enode = NULL;

    expr_enode = new_enode_typed( tnode, ex );
    enode_list_push( &c->e_stack, expr_enode );
}

static void compiler_push_error_type( COMPILER *c,
				   cexception_t *ex )
{
    ENODE *expr_enode = NULL;

    expr_enode = new_enode( ex );
    enode_set_has_errors( expr_enode );
    enode_list_push( &c->e_stack, expr_enode );
}

static void compiler_append_expression_type( COMPILER *c,
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

static void compiler_compile_exception( COMPILER *c,
				     char *exception_name,
				     ssize_t exception_nr,
				     cexception_t *ex )
{
    cexception_t inner;
    DNODE *volatile exception = NULL;
    DNODE *volatile shared_exception = NULL;
    TNODE *volatile exception_type =
	share_tnode( typetab_lookup( c->typetab, "exception" ));

    cexception_guard( inner ) {
	exception =
	    new_dnode_exception( exception_name, exception_type, &inner );
        exception_type = NULL;

	dnode_set_ssize_value( exception, exception_nr );
        shared_exception = share_dnode( exception );
	vartab_insert_named( c->vartab, &shared_exception, &inner );
        if( c->current_module && dnode_scope( exception ) == 0 ) {
            dnode_vartab_insert_named_vars( c->current_module,
                                            &exception, &inner );
        } else {
            dispose_dnode( &exception );
        }
    }
    cexception_catch {
	delete_dnode( exception );
	delete_dnode( shared_exception );
        delete_tnode( exception_type );
	cexception_reraise( inner, ex );
    }
}

static void compiler_compile_next_exception( COMPILER *c,
					  char *exception_name,
					  cexception_t *ex )
{
    compiler_compile_exception( c, exception_name, ++c->latest_exception_nr, ex );
}

static void compiler_push_array_of_type( COMPILER *c, TNODE *tnode,
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

static void compiler_drop_top_expression( COMPILER *cc )
{
    assert( cc->e_stack );
    enode_list_drop( &cc->e_stack );
}

static void compiler_swap_top_expressions( COMPILER *cc )
{
    ENODE *e1 = enode_list_pop( &cc->e_stack );
    ENODE *e2 = enode_list_pop( &cc->e_stack );

    enode_list_push( &cc->e_stack, e1 );
    enode_list_push( &cc->e_stack, e2 );    
}

static void compiler_check_and_remove_index_type( COMPILER *cc )
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

static void compiler_emit( COMPILER *cc,
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

static key_value_t *make_tnode_key_value_list( TNODE *tnode,
                                               TNODE *element_tnode )
{
    static key_value_t empty_list[1] = {{ NULL }};
    static key_value_t list[] = {
	/* 0 */ { "element_nref" },
        /* 1 */ { "element_size" },
        /* 2 */ { "element_align" },
        /* 3 */ { "nref" },
        /* 4 */ { "alloc_size" },
        /* 5 */ { "vmt_offset" },
	{ NULL },
    };

    if( !tnode && !element_tnode ) return empty_list;

    if( !element_tnode )
        element_tnode = tnode_element_type( tnode );

    if( element_tnode ) {
        /* For placeholders, we just in case allocate arrays thay say
           they contain references. This is necessary so that GC does
           not collect allocated elements in case the generic type is
           indeed a reference, and we assign them as elements to an
           allocated array of generic type: */

        list[0].val = tnode_is_reference( element_tnode ) ? 1 : 
            (tnode_kind(element_tnode) == TK_PLACEHOLDER ? 1 : 0);

        list[1].val = tnode_is_reference( element_tnode ) ? 
            REF_SIZE : tnode_size( element_tnode );
        list[2].val = tnode_align( element_tnode );

    } else {
        list[0].val = list[1].val = list[2].val = 0;
    }

    if( tnode ) {
        list[3].val = tnode_number_of_references( tnode );
        list[4].val = tnode_size( tnode );
        list[5].val = tnode_vmt_offset( tnode );
    } else {
        list[3].val = list[4].val = list[5].val = 0;
    }

    return list;
}
 
static ssize_t compiler_assemble_static_data( COMPILER *cc,
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

#define ALIGN_NUMBER(N,lim)  ( (N) += ((lim) - ((ssize_t)(N)) % (lim)) % (lim) )

static void compiler_assemble_static_alloc_hdr( COMPILER *cc,
                                                ssize_t element_size,
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
    alloccell_set_values( hdr, element_size, len );
}

static ssize_t compiler_assemble_static_ssize_t( COMPILER *cc,
						 ssize_t size,
						 cexception_t *ex )
{
    return compiler_assemble_static_data( cc, &size, sizeof(size), ex );
}

static ssize_t compiler_assemble_static_string( COMPILER *cc,
						char *str,
						cexception_t *ex )
{
    compiler_assemble_static_alloc_hdr( cc, 1, strlen(str) + 1, ex );
    return compiler_assemble_static_data( cc, str, strlen(str) + 1, ex );
}

static
const char *skip_leading_spaces( const char *s )
{
    while( isspace(*s) ) s++;
    return s;
}

static 
key_value_t *make_compiler_tnode_key_value_list( COMPILER *cc,
                                                 TNODE *tnode,
                                                 cexception_t *ex )
{
    static key_value_t empty_list[1] = {{ NULL }};
    static key_value_t list[] = {
	/* 0 */ { "element_nref" },
        /* 1 */ { "element_size" },
        /* 2 */ { "element_align" },
        /* 3 */ { "nref" },
        /* 4 */ { "alloc_size" },
        /* 5 */ { "vmt_offset" },
        /* 6 */ { "lineno" },
        /* 7 */ { "line" },
        /* 8 */ { "file" },
	{ NULL },
    };

    if( !tnode ) return empty_list;

    list[0].val = tnode_is_reference( tnode ) ? 1 : 0;
    list[1].val = tnode_is_reference( tnode ) ? 
        REF_SIZE : tnode_size( tnode );
    list[2].val = tnode_align( tnode );

    list[3].val = tnode_number_of_references( tnode );
    list[4].val = tnode_size( tnode );
    list[5].val = tnode_vmt_offset( tnode );

    list[6].val = compiler_flex_current_line_number();
    list[7].val = compiler_assemble_static_string
        ( cc, (char*)skip_leading_spaces(compiler_flex_current_line()), ex );
    list[8].val = compiler_assemble_static_string
        ( cc, (char*)cc->filename, ex );;

    /* For placeholders, we just in case allocate arrays thay say they
       contain references. This is necessary so that GC does not
       collect allocated elements in case the generic type is indeed a
       reference, and we assign them as elements to an allocated array
       of generic type: */

    list[0].val = tnode_is_reference( tnode ) ? 1 : 
        (tnode_kind(tnode) == TK_PLACEHOLDER ? 1 : 0);

    return list;
}

static key_value_t *make_mdalloc_key_value_list( TNODE *tnode, ssize_t level )
{
    static key_value_t empty_list[1] = {{ NULL }};
    static key_value_t list[] = {
	{ "element_nref" },
	{ "level" },
        { "element_size" },
        { "element_align" },
	{ NULL },
    };

    if( !tnode ) return empty_list;

    list[0].val = tnode_is_reference( tnode ) ? 1 : 0;
    list[1].val = level;
    list[2].val = tnode_is_reference( tnode ) ? 
        REF_SIZE : tnode_size( tnode );
    list[3].val = tnode_align( tnode );

    return list;
}

static void compiler_fixup_inlined_function( COMPILER *cc,
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

static void compiler_emit_function_call( COMPILER *cc,
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
		compiler_emit( cc, ex, "\tc\n", PUSHFRM );
                code_start ++;
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
		compiler_emit( cc, ex, "\n\tc\n", POPFRM );
	    }
	}
	if( fixup_values ) {
	    compiler_fixup_inlined_function( cc, function, fixup_values,
                                             code_start );
	}
    } else {
	TNODE *fn_tnode = function ? dnode_type( function ) : NULL;
        type_kind_t fn_kind = fn_tnode ? tnode_kind( fn_tnode ) : TK_NONE;

	if( fn_kind == TK_FUNCTION_REF || fn_kind == TK_CLOSURE ) {
	    compiler_emit( cc, ex, "\tc\n", ICALL );
	} else if( fn_tnode && tnode_kind( fn_tnode ) == TK_METHOD ) {
	    char *fn_name = dnode_name( function );
	    ssize_t fn_address = dnode_offset( function );
	    ssize_t interface_nr = tnode_interface_number( fn_tnode );
            if( cc->current_interface_nr < 0 ) {
                interface_nr = cc->current_interface_nr - 1;
            }
	    compiler_emit( cc, ex, "\tceeN\n", VCALL,
			&interface_nr, &fn_address, fn_name );
	} else {
	    char *fn_name = dnode_name( function );
	    ssize_t fn_address = dnode_offset( function );
	    ssize_t zero = 0;
	    if( fn_address == 0 && fn_name ) {
		thrcode_push_forward_function( cc->thrcode, fn_name,
					       thrcode_length( cc->thrcode ) + 1,
					       ex );
		compiler_emit( cc, ex, "\tceN\n", CALL, &zero, fn_name );
	    } else {
		/* ssize_t code_length = thrcode_length( compiler->thrcode ); */
		/* fn_address -= code_length; */
		compiler_emit( cc, ex, "\tceN\n", CALL, &fn_address, fn_name );
	    }
	}
    }
}

static void compiler_push_function_retvals( COMPILER *cc, DNODE *function,
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

static DNODE* compiler_lookup_conversion( COMPILER *cc,
                                          TNODE *target_type,
                                          TNODE *src_type )
{
    TLIST *conversion_argument = NULL;
    TNODE *source_type = src_type;
    cexception_t *ex = NULL; /* FIXME: make 'ex' an argument */

#if 0
    printf( ">>> looking up conversion from '%s' to '%s'\n",
            target_type ? tnode_name(src_type) : "<null>",
            target_type ? tnode_name(target_type) : "<null>" );
#endif

    tlist_push_tnode( &conversion_argument, &source_type, ex );

    DNODE *conversion_dnode =
        target_type ?
        vartab_lookup_operator( cc->operators, tnode_name( target_type ),
                                conversion_argument ) : NULL;

    if( conversion_dnode ) {
        return conversion_dnode;
    } else {
        return tnode_lookup_conversion( target_type, src_type );
    }
}

static void compiler_compile_type_conversion( COMPILER *cc,
                                              TNODE *target_type,
                                              char *target_name,
                                              cexception_t *ex )
{
    cexception_t inner;
    ENODE * volatile expr = enode_list_pop( &cc->e_stack );
    ENODE * volatile converted_expr = NULL;
    TNODE * expr_type = expr ? enode_type( expr ) : NULL;
    char *source_name = expr_type ? tnode_name( expr_type ) : NULL;

    if( !target_name && target_type ) {
        target_name = tnode_name( target_type );
    }

    cexception_guard( inner ) {
	if( !expr ) {
	    yyerrorf( "not enough values on the stack for type conversion "
		      "from '%s' to '%s'", source_name, target_name );
	} else {
	    DNODE *conversion =
		target_type ?
                compiler_lookup_conversion( cc, target_type, expr_type ) :
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
                key_value_t *fixup_values = NULL;

                TNODE *element_tnode = tnode_element_type( target_type );
                if( element_tnode ) {
                    fixup_values = make_tnode_key_value_list( target_type, element_tnode );
                }

		compiler_emit_function_call( cc, conversion, fixup_values, "\n", ex );
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

static void compiler_compile_named_type_conversion( COMPILER *cc,
                                                    char *target_name,
                                                    cexception_t *ex )
{
    TNODE *target_type =
        typetab_lookup( cc->typetab, target_name );

    compiler_compile_type_conversion( cc, target_type, target_name, ex );
}

static void compiler_compile_return( COMPILER *cc,
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

    retval = dnode_list_last( fn_retvals );
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
        char msg[300] = "";
	if( !tnode_types_are_assignment_compatible
            ( returned_type, available_type, NULL /* generic type table */,
              msg, sizeof(msg)-1, ex )) {
            char *returned_type_name = returned_type ?
                tnode_name( returned_type ) : NULL;
            if( available_type && returned_type_name && 
                i == 0 &&
                compiler_lookup_conversion( cc, returned_type,
                                            available_type  )) {
                compiler_compile_named_type_conversion( cc, returned_type_name, ex );
                expr = cc->e_stack;
                if( expr ) {
                    available_type = enode_type( expr );
                }
            } else {
                if( msg[0] ) {
                    yyerrorf( "incompatible types of returned value %d "
                              "of function '%s' - %s",
                              nretvals - i, dnode_name( cc->current_function ),
                              msg );
                } else {
                    yyerrorf( "incompatible types of returned value %d "
                              "of function '%s'",
                              nretvals - i, dnode_name( cc->current_function ));
                }
            }
	}

	retval = dnode_prev( retval );
	expr = enode_next( expr );
    }

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
	    compiler_emit( cc, ex, "\tc\n", RESTORE );
	}
    }

    if( function && !dnode_has_flags( function, DF_INLINE )) {
	compiler_emit( cc, ex, "\tc\n", RET );
    }
}

static DNODE *
compiler_lookup_optab_operator( COMPILER *cc,
                                char *operator_name,
                                TNODE *argument_tnode,
                                int arity,
                                cexception_t *ex )
{
    cexception_t inner;
    ENODE *top_expr = cc->e_stack;
    ENODE *expr = NULL;
    TNODE *current = NULL;
    TLIST *volatile expr_types = NULL; 
    DNODE *operator_dnode = NULL;
    int i = 0;

    cexception_guard( inner ) {
        if( !top_expr && strcmp( operator_name, "st" ) == 0 ) {
            share_tnode( argument_tnode );
            tlist_push_tnode( &expr_types, &argument_tnode, &inner );
        } else {
            for( expr = top_expr; expr; expr = enode_next( expr )) {
                if( enode_has_flags( expr, EF_GUARDING_ARG )) {
                    break;
                }
                current = share_tnode( enode_type( expr ));
                tlist_push_tnode( &expr_types, &current, &inner );
                i++;
                if( i >= arity ) break;
            }
        }
    }
    cexception_catch {
        delete_tlist( expr_types );
        cexception_reraise( inner, ex );
    }

    operator_dnode = vartab_lookup_operator( cc->operators, operator_name,
                                             expr_types );

    delete_tlist( expr_types );

    return operator_dnode;
}

static DNODE* compiler_lookup_operator( COMPILER *cc,
                                        TNODE *tnode,
                                        char *operator_name,
                                        int arity,
                                        cexception_t *ex )
{
    DNODE *operator;

    if( (operator = compiler_lookup_optab_operator( cc, operator_name,
                                                    tnode, arity, ex ))) {
        return operator;
    } else {
        return tnode_lookup_operator( tnode, operator_name, arity );
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

static void compiler_init_operator_description( operator_description_t *od,
                                             COMPILER *cc,
					     TNODE *op_type,
					     char *op_name,
					     int arity,
                                             cexception_t *ex )
{
    assert( od );

    memset( od, 0, sizeof(*od) );

    od->magic = OD_MAGIC;
    od->flags = ODF_NONE;
    od->name = op_name;
    od->arity = arity;
    od->containing_type = op_type;
    od->operator = 
        compiler_lookup_optab_operator( cc, op_name, op_type, arity, ex );
    if( !od->operator ) {
        od->operator = op_type ?
            tnode_lookup_operator_nonrecursive( op_type, op_name, arity )
            : NULL;
    }
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

static void compiler_check_operator_args( COMPILER *cc,
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

        if( strcmp( od->name, "st" ) == 0 ) {
            /* The custom "st" operators will be emitted when
               compiling function parameter list (stores); at that
               point there will be no expressions emulated on the
               e_stack, and the compatibility check needs a special
               treatment: */
            TNODE *arg_type = op_args ? dnode_type( op_args ) : NULL;

            char msg[300] = "";
            if( !arg_type ||
                !tnode_types_are_assignment_compatible( dnode_type( op_args ),
                                                        od->containing_type,
                                                        generic_types,
                                                        msg, sizeof(msg)-1,
                                                        ex )) {
                if( msg[0] ) {
                    yyerrorf( "incompatible type of an argument "
                              "for operator '%s' - %s", od->name, msg );
                } else {
                    yyerrorf( "incompatible type of an argument "
                              "for operator '%s'", od->name );
                }
            }
        } else {
            expr = cc->e_stack;

            nargs = dnode_list_length( op_args );

            foreach_reverse_dnode( arg, op_args ) {
                TNODE *argument_type;
                TNODE *expr_type;

                if( !expr ) {
                    yyerrorf( "too little values on the stack for the operator '%s'",
                              dnode_name( od->operator ));
                    break;
                }

                argument_type = dnode_type( arg );
                expr_type = enode_type( expr );

#if 0
                if( strcmp( od->name, "[]" ) == 0 ) {
                fprintf( stderr, ">>> %s(): '%s': arg = '%s', targ = '%s' (%s), "
                         "expr = '%s' (%s)\n",
                         cc->current_function ? dnode_name(cc->current_function):"<main>",
                         od->name, dnode_name(arg),
                         tnode_name(argument_type),
                         tnode_kind_name(argument_type),
                         tnode_name(expr_type),
                         tnode_kind_name(expr_type)
                );
                }
#endif
                if( !tnode_types_are_compatible( argument_type, expr_type,
                                                 generic_types, ex )) {
                    yyerrorf( "incompatible type of argument %d "
                              "for operator '%s'",
                              nargs, dnode_name( od->operator ));
                }

                expr = enode_next( expr );
                nargs --;
            }
	}
    }
}

static void compiler_drop_operator_args( COMPILER *cc,
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

static void compiler_push_operator_retvals( COMPILER *cc,
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
	    ( tnode_kind( od->containing_type ) == TK_DERIVED ||
	      tnode_kind( od->containing_type ) == TK_ENUM ) &&
	    (od->flags & ODF_IS_INHERITED) != 0 ) {
	TNODE *curr_type = od->containing_type;
        while( tnode_has_flags( curr_type, TF_IS_EQUIVALENT ) &&
               (curr_type = tnode_base_type( curr_type )) != NULL );
        TNODE *base_type = tnode_base_type( curr_type );
	if( retval_type == base_type ) {
	    retval_type = od->containing_type;
	}
    }

    if( generic_types ) {
#if 0
    // if( 0 ) {
        // CHECK MEMORY USAGE HERE!!! S.G.
#endif
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
	compiler_push_typed_expression( cc, retval_type, ex );
	share_tnode( retval_type );
    }  else {
	if( !od->operator && on_error_expr && *on_error_expr ) {
	    enode_set_has_errors( *on_error_expr );
	    enode_list_push( &cc->e_stack, *on_error_expr );
	    *on_error_expr = NULL; /* let's not delete expression :) */
	}
    }
}

static void compiler_emit_operator_or_report_missing( COMPILER *cc,
                                                      operator_description_t *od,
                                                      key_value_t *fixup_values,
                                                      char *trailer,
                                                      cexception_t *ex )
{
    assert( od );
    assert( od->magic == OD_MAGIC );

    if( od->operator ) {
	compiler_emit_function_call( cc, od->operator, fixup_values, trailer, ex );
    } else {
	tnode_report_missing_operator( od->containing_type,
				       od->name, od->arity );
    }
}

static void compiler_check_operator_retvals( COMPILER *cc,
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

static int compiler_test_top_types_are_identical( COMPILER *cc,
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

static int compiler_test_top_types_are_assignment_compatible(
    COMPILER *cc,
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

	if( !tnode_types_are_assignment_compatible
            ( type1, type2, NULL /* generic type table */,
              NULL /* msg */, 0 /* msglen */, ex )) {
	    return 0;
	} else {
	    return 1;
	}
    }    
}

static int compiler_test_top_types_are_readonly_compatible_for_copy(
    COMPILER *cc,
    cexception_t *ex )
{
    ENODE * expr1 = NULL, * expr2 = NULL;

    assert( cc );

    expr1 = cc->e_stack;
    expr2 = expr1 ? enode_next( expr1 ) : NULL;

    if( !expr1 || !expr2 ) {
	return 0;
    } else {
        TNODE *tnode2 = enode_type( expr2 );
	if( enode_has_flags( expr2, EF_IS_READONLY ) ||
            ( tnode2 && tnode_is_immutable( tnode2 ))) {
	    return 0;
	} else {
            return 1;
	}
    }
}

static int compiler_check_top_2_expressions_are_identical( COMPILER *cc,
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
#if 0
	TNODE *type1 = enode_type( expr1 );
	TNODE *type2 = enode_type( expr2 );

	if( strcmp( binop_name, "%%" ) != 0 && 
	    !tnode_types_are_identical( type1, type2, NULL, ex )) {
	    yyerrorf( "incompatible types for binary operator '%s'",
		      binop_name );
	    return 0;
	}
#endif
	return 1;
    }
}

static void compiler_check_top_2_expressions_and_drop( COMPILER *cc,
						       char *binop_name,
						       cexception_t *ex )
{
    compiler_check_top_2_expressions_are_identical( cc, binop_name, ex );
    if( cc->e_stack )
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

static void compiler_compile_binop( COMPILER *cc,
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

	    compiler_init_operator_description( &od, cc, type1,
                                             binop_name, 2, ex );
	    if( !od.operator ) {
		TNODE *type2 = enode_type( expr2 );
		compiler_init_operator_description( &od, cc, type2,
                                                 binop_name, 2, ex );
	    }

	    if( stack_is_ok ) {
		compiler_check_operator_args( cc, &od, generic_types, &inner );
	    }

	    top1 = enode_list_pop( &cc->e_stack );
	    top2 = enode_list_pop( &cc->e_stack );

	    compiler_emit_operator_or_report_missing( cc, &od, NULL, "\n",
                                                      &inner );
	    compiler_check_operator_retvals( cc, &od, 1, 1 );
	    compiler_push_operator_retvals( cc, &od, &top2, generic_types,
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

static void compiler_compile_unop( COMPILER *cc,
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
	    key_value_t *fixup_values = NULL;
            if( expr_type && tnode_kind( expr_type ) == TK_ARRAY ) {
		fixup_values = make_tnode_key_value_list( expr_type, NULL );
            } else {
                fixup_values =
                    make_compiler_tnode_key_value_list( cc, expr_type, ex );
            }

	    compiler_init_operator_description( &od, cc, expr_type,
                                                unop_name, 1, ex );
	    compiler_check_operator_args( cc, &od, generic_types, &inner );

	    top = enode_list_pop( &cc->e_stack );

	    compiler_emit_operator_or_report_missing( cc, &od, fixup_values,
                                                      "\n", ex );
	    compiler_check_operator_retvals( cc, &od, 0, 1 );
	    compiler_push_operator_retvals( cc, &od, &top, generic_types, &inner );
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

static void compiler_emit_st( COMPILER *cc,
                              TNODE *expr_type,
                              char *var_name,
                              ssize_t var_offset,
                              int var_scope,
                              cexception_t *ex )
{
    operator_description_t od;

    if( var_scope == compiler_current_scope( cc )) {

	compiler_init_operator_description( &od, cc, expr_type, "st", 1, ex );
	compiler_check_operator_args( cc, &od, NULL /*generic_types*/, ex );

	if( od.operator ) {
	    compiler_emit_function_call( cc, od.operator, NULL, "", ex );
	    compiler_emit( cc, ex, "eN\n", &var_offset, var_name );
	} else {
	    if( tnode_is_reference( expr_type )) {
		compiler_emit( cc, ex, "\tceN\n", PST, &var_offset, var_name );
	    } else {
		compiler_emit( cc, ex, "\tceN\n", ST, &var_offset, var_name );
	    }
	}
    } else {
	if( var_scope == 0 ) {
	    compiler_init_operator_description( &od, cc, expr_type, "stg", 1, ex );
	    compiler_check_operator_args( cc, &od, NULL /*generic_types*/, ex );

	    if( od.operator ) {
		compiler_emit_function_call( cc, od.operator, NULL, "", ex );
		compiler_emit( cc, ex, "eN\n", &var_offset, var_name );
	    } else {
		if( tnode_is_reference( expr_type )) {
		    compiler_emit( cc, ex, "\tceN\n", PSTG, &var_offset, var_name );
		} else {
		    compiler_emit( cc, ex, "\tceN\n", STG, &var_offset, var_name );
		}
	    }
	} else {
	    yyerrorf( "can only store variables in the current scope"
		      "or in the scope 0" );
	}
    }

    compiler_check_operator_retvals( cc, &od, 0, 0 );
}

static void compiler_compile_variable_assignment_or_init(
    COMPILER *cc,
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

        /* TYPETAB *generic_types = new_typetab( ex ); */
        TYPETAB *generic_types = NULL;
        int has_errors = 0;
        char msg[300] = "";
        if( !tnode_types_are_assignment_compatible( var_type, expr_type, 
                                                    generic_types,
                                                    msg, sizeof(msg)-1, ex )) {
	    char *dst_name = var_type ? tnode_name( var_type ) : NULL;
	    if( expr_type && dst_name &&
		compiler_lookup_conversion( cc, var_type, expr_type )) {
		compiler_compile_named_type_conversion( cc, dst_name, ex );
		expr = cc->e_stack;
		expr_type = enode_type( expr );
	    } else {
		if( var_name ) {
                    if( msg[0] ) {
                        yyerrorf( "incompatible types for assignment to "
                                  "variable '%s' - %s", var_name, msg );
                    } else {
                        yyerrorf( "incompatible types for assignment to "
                                  "variable '%s'", var_name );
                    }
		} else {
                    if( msg[0] ) {
                        yyerrorf( "incompatible types for assignment to "
                                  "variable - %s", msg );
                    } else {
                        yyerrorf( "incompatible types for assignment to "
                                  "variable" );
                    }
		}
                has_errors = 1;
	    }
	}
        if( variable && !has_errors ) {
            if( !(*enode_is_readonly_compatible)( expr, variable )) {
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
                compiler_emit_st( cc, expr_type, var_name, var_offset,
                                  var_scope, ex );
            }
        }
        delete_typetab( generic_types );
        compiler_drop_top_expression( cc );
    }
}

static void compiler_compile_variable_assignment( COMPILER *cc,
                                                  DNODE *variable,
                                                  cexception_t *ex )
{
    compiler_compile_variable_assignment_or_init(
        cc, variable, enode_is_readonly_compatible_with_var, ex );
}

static void compiler_compile_variable_initialisation( COMPILER *cc,
                                                      DNODE *variable,
                                                      cexception_t *ex )
{
    compiler_compile_variable_assignment_or_init(
        cc, variable, enode_is_readonly_compatible_for_init, ex );
}

static void compiler_compile_store_variable( COMPILER *cc,
                                             DNODE *varnode,
                                             cexception_t *ex )
{
    if( varnode ) {
        compiler_compile_variable_assignment( cc, varnode, ex );
    } else {
        compiler_emit( cc, ex, "\tcNN\n", ST, "???", "???" );
    }
}

static void compiler_compile_initialise_variable( COMPILER *cc,
                                                  DNODE *varnode,
                                                  cexception_t *ex )
{
    if( varnode ) {
        compiler_compile_variable_initialisation( cc, varnode, ex );
    } else {
        compiler_emit( cc, ex, "\tcNN\n", ST, "???", "???" );
    }
}

static void compiler_stack_top_dereference( COMPILER *cc )
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

static int compiler_stack_top_is_addressof( COMPILER *cc )
{
    ENODE *enode = cc ? cc->e_stack : NULL;
    TNODE *etype = enode ? enode_type( enode ) : NULL;
    return etype ? tnode_is_addressof( etype ) : 0;
}

static void compiler_compile_ldi( COMPILER *cc, cexception_t *ex )
{
    ENODE * volatile expr;

    expr = cc->e_stack;

    if( !compiler_stack_top_is_addressof( cc )) return;

    if( !expr ) {
	yyerrorf( "not enough values on the stack for indirect load (LDI)" );
    } else {
	TNODE *expr_type = enode_type( expr );
	TNODE *element_type =
	    expr_type ? tnode_element_type( expr_type ) : NULL;
	operator_description_t od;

	compiler_init_operator_description( &od, cc, element_type,
                                            "ldi", 1, ex );

	if( !expr_type || tnode_kind( expr_type ) != TK_ADDRESSOF ) {
	    yyerrorf( "lvalue is needed for indirect load (LDI)" );
	} else {
	    compiler_check_operator_args( cc, &od, NULL /*generic_types*/, ex );
	}

	if( od.operator ) {
	    cexception_t inner;

	    expr = enode_list_pop( &cc->e_stack );
	    cexception_guard( inner ) {
		compiler_emit_function_call( cc, od.operator, NULL, "\n", &inner );
		compiler_check_operator_retvals( cc, &od, 1, 1 );
		compiler_push_operator_retvals( cc, &od, &expr,
                                             NULL /*generic_types*/, &inner );
	    }
	    cexception_catch {
		delete_enode( expr );
		cexception_reraise( inner, ex );
	    }
	    dispose_enode( &expr );
	} else {
	    TNODE *element_type =
		expr_type ? tnode_element_type( expr_type ) : NULL;
	    ssize_t element_size =
		element_type ? 
                ( tnode_is_reference( element_type ) ? 
                  REF_SIZE : tnode_size( element_type )) : 0;
	    char *name = element_type ? tnode_name( element_type ) : NULL;

	    if( element_size > sizeof(union stackunion)) {
		if( name ) {
		    yyerrorf( "value of type '%s' is too large to be loaded "
			      "onto the stack", name );
		} else {
		    yyerrorf( "value to be loaded by LDI is too large "
			      "to fit onto the stack" );
		}
	    }

	    if( element_type && !tnode_is_reference( element_type ) &&
		tnode_number_of_references( element_type ) > 0 ) {
		yyerrorf( "values with references should not be loaded "
			  "onto the stack" );
	    }

            if( element_type && tnode_kind( element_type ) == TK_PLACEHOLDER ) {
		compiler_emit( cc, ex, "\tc\n", GLDI );
	    } else if( element_type && tnode_is_reference( element_type )) {
		compiler_emit( cc, ex, "\tc\n", PLDI );
	    } else {
		compiler_emit( cc, ex, "\tcs\n", LDI, &element_size );
	    }
	    compiler_stack_top_dereference( cc );
	}
    }
}

static void compiler_compile_sti( COMPILER *cc, cexception_t *ex )
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

            char msg[300] = "";
	    if( element_type && expr_type ) {
		/* if( !tnode_types_are_identical( element_type, expr_type )) {
		 */
		if( !tnode_types_are_assignment_compatible
                    ( element_type, expr_type, NULL /* generic_type_table*/,
                      msg, sizeof(msg)-1, ex )) {
		    char *dst_name = tnode_name( element_type );
		    if( expr_type && dst_name &&
			compiler_lookup_conversion( cc, element_type, 
                                                    expr_type )) {
			compiler_compile_named_type_conversion( cc, dst_name, ex );
			expr = cc->e_stack;
                        expr_type = enode_type( expr );
		    } else {
                        if( msg[0] ) {
                            yyerrorf( "incompatible types for assignment - %s",
                                      msg );
                        } else {
                            yyerrorf( "incompatible types for assignment" );
                        }
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

	    compiler_init_operator_description( &od, cc, expr_type, "sti", 2, ex );

	    if( ( !addr_type || tnode_kind( addr_type ) != TK_ADDRESSOF ) &&
                !enode_has_errors( lval )) {
		yyerrorf( "lvalue is needed for assignment" );
	    } else {
		compiler_check_operator_args( cc, &od, NULL /*generic_types*/,
                                              &inner );
	    }

	    top1 = enode_list_pop( &cc->e_stack );
	    top2 = enode_list_pop( &cc->e_stack );

	    if( od.operator ) {
		compiler_emit_function_call( cc, od.operator, NULL, "\n", &inner );
		compiler_check_operator_retvals( cc, &od, 0, 0 );
	    } else {
                ssize_t expr_size = expr_type ? tnode_size( expr_type ) : 0;
		if( expr_type && tnode_kind( expr_type ) == TK_PLACEHOLDER ) {
		    compiler_emit( cc, &inner, "\tc\n", GSTI );
                } else if( expr_type && tnode_is_reference( expr_type )) {
		    compiler_emit( cc, &inner, "\tc\n", PSTI );
		} else {
		    compiler_emit( cc, &inner, "\tcs\n", STI, &expr_size );
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

static void compiler_duplicate_top_expression( COMPILER *cc,
					       cexception_t *ex )
{
    ENODE *expr;

    expr = cc->e_stack;

    if( !expr ) {
	yyerrorf( "not enough values on the stack for duplication "
		  "of expression" );
    } else {
	TNODE *expr_type = enode_type( expr );
	compiler_push_typed_expression( cc, share_tnode( expr_type ), ex );
    }
}

static void compiler_compile_operator( COMPILER *cc,
                                       TNODE *tnode,
                                       char *operator_name,
                                       int arity,
                                       cexception_t *ex )
{
    operator_description_t od;

    compiler_init_operator_description( &od, cc, tnode, operator_name, arity, ex );
    compiler_emit_operator_or_report_missing( cc, &od, NULL, "", ex );
    compiler_check_operator_retvals( cc, &od, 0, 1 );
    compiler_push_operator_retvals( cc, &od, NULL, NULL /* generic_types */, ex );
}

static void compiler_check_and_compile_operator( COMPILER *cc,
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
	compiler_init_operator_description( &od, cc, tnode, 
                                         operator_name, arity, ex );
	compiler_check_operator_args( cc, &od, generic_types, ex );
	compiler_drop_operator_args( cc, &od );
	compiler_emit_operator_or_report_missing( cc, &od, fixup_values, "", ex );
	compiler_check_operator_retvals( cc, &od, 0, 1 );
	compiler_push_operator_retvals( cc, &od, NULL, generic_types, ex );
    }
    cexception_catch {
	delete_typetab( generic_types );
	cexception_reraise( inner, ex );
    }
    delete_typetab( generic_types );
}

static void compiler_check_and_compile_top_operator( COMPILER *cc,
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
	ENODE *left_expr = expr ? enode_next( expr ) : NULL;
	if( arity > 1 ) {
	    if( !left_expr ) {
		yyerrorf( "no left operand for binary operator '%s'?",
			  operator );
	    }
	}
	compiler_check_and_compile_operator( cc, tnode, operator, arity, 
					  /*fixup_values:*/ NULL, ex );
    }
}

static void compiler_check_and_compile_top_2_operator( COMPILER *cc,
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
	if( compiler_lookup_operator( cc, tnode2, operator, arity, ex )) {
	    key_value_t *fixup_values =
                make_tnode_key_value_list( tnode2, NULL );

	    compiler_check_and_compile_operator( cc, tnode2, operator, arity,
                                                 fixup_values, ex );
	} else {
	    compiler_check_and_compile_operator( cc, tnode, operator, arity, 
                                                 /*fixup_values:*/ NULL, ex );
	}
    }
}

static void compiler_compile_dup( COMPILER *cc, cexception_t *ex )
{
    ENODE *expr;

    expr = cc->e_stack;

    if( !expr ) {
	yyerrorf( "not enough values on the stack for duplication (DUP)" );
    } else {
	TNODE *expr_type = enode_type( expr );
	operator_description_t od;

	compiler_init_operator_description( &od, cc, expr_type, "dup", 1, ex );

	if( od.operator ) {
	    ENODE *new_expr = expr;
	    compiler_emit_function_call( cc, od.operator, NULL, "\n", ex );
	    compiler_check_operator_args( cc, &od, NULL /*generic_types*/,
                                          ex );
	    compiler_check_operator_retvals( cc, &od, 1, 1 );
	    compiler_push_operator_retvals( cc, &od, &new_expr,
                                            NULL /* generic_types */, ex );
	    if( !new_expr ) {
		share_enode( expr );
	    }
	} else {
	    compiler_emit( cc, ex, "\tc\n", DUP );
	    compiler_push_typed_expression( cc, expr_type, ex );
	    share_tnode( expr_type );
	}
    }
}

static int compiler_dnode_is_reference( COMPILER *cc, DNODE *dnode )
{
    return dnode ? dnode_type_is_reference( dnode ) : 0;
}

static int compiler_stack_top_is_integer( COMPILER *cc )
{
    ENODE *enode = cc ? cc->e_stack : NULL;
    TNODE *etype = enode ? enode_type( enode ) : NULL;
    return etype ? tnode_is_integer( etype ) : 0;
}

static int compiler_stack_top_is_reference( COMPILER *cc )
{
    ENODE *enode = cc ? cc->e_stack : NULL;
    TNODE *etype = enode ? enode_type( enode ) : NULL;
    return etype ? tnode_is_reference( etype ) : 0;
}

static int compiler_stack_top_base_is_reference( COMPILER *cc )
{
    ENODE *enode = cc ? cc->e_stack : NULL;
    TNODE *etype = enode ? enode_type( enode ) : NULL;
    TNODE *ebase = etype ? tnode_element_type( etype ) : NULL;
    return ebase ? tnode_is_reference( ebase ) : 0;
}
 
static int compiler_stack_top_is_array( COMPILER *cc )
{
    ENODE *enode = cc ? cc->e_stack : NULL;
    TNODE *etype = enode ? enode_type( enode ) : NULL;
    return etype ? tnode_kind( etype ) == TK_ARRAY : 0;
}

static int compiler_stack_top_has_references( COMPILER *cc,
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

static void compiler_compile_drop( COMPILER *cc, cexception_t *ex )
{
    if( compiler_stack_top_is_reference( cc )) {
	compiler_emit( cc, ex, "\tc\n", PDROP );
    } else {
	compiler_emit( cc, ex, "\tc\n", DROP );
    }
    compiler_drop_top_expression( cc );
}

static void compiler_compile_dropn( COMPILER *cc,
				 ssize_t drop_values,
				 cexception_t *ex )
{
    ssize_t i;

    if( compiler_stack_top_has_references( cc, drop_values )) {
	compiler_emit( cc, ex, "\tce\n", PDROPN, &drop_values );
    } else {
	compiler_emit( cc, ex, "\tce\n", DROPN, &drop_values );
    }
    for( i = 0; i < drop_values; i ++ ) {
	compiler_drop_top_expression( cc );
    }
}

static void compiler_compile_swap( COMPILER *cc, cexception_t *ex )
{
    ENODE *expr1 = enode_list_pop( &cc->e_stack );
    ENODE *expr2 = enode_list_pop( &cc->e_stack );

    if( !expr1 || !expr2 ) {
	yyerrorf( "not enough values on the stack for SWAP" );
    }
    
    enode_list_push( &cc->e_stack, expr1 );
    enode_list_push( &cc->e_stack, expr2 );

    compiler_emit( cc, ex, "\tc\n", SWAP );
}

static void compiler_compile_rot( COMPILER *cc, cexception_t *ex )
{
    ENODE *expr1 = enode_list_pop( &cc->e_stack );
    ENODE *expr2 = enode_list_pop( &cc->e_stack );
    ENODE *expr3 = enode_list_pop( &cc->e_stack );

    if( !expr1 || !expr2 || !expr3 ) {
	yyerrorf( "not enough values on the stack for SWAP" );
    }
    
    enode_list_push( &cc->e_stack, expr1 );
    enode_list_push( &cc->e_stack, expr3 );
    enode_list_push( &cc->e_stack, expr2 );

    compiler_emit( cc, ex, "\tc\n", ROT );
}

static void compiler_compile_peek( COMPILER *cc, ssize_t offset,
                                   cexception_t *ex )
{
    ENODE *expr = cc->e_stack;
    ssize_t count = offset;

    while( expr && count > 1 ) {
        expr = enode_next( expr );
        count --;
    }

    if( expr ) {
        TNODE *expr_type = enode_type( expr );
        compiler_push_typed_expression( cc, share_tnode( expr_type ), ex );
        compiler_emit( cc, ex, "\tce\n", PEEK, &offset );
    } else {
        yyerrorf( "not enough expressions on the evaluation stack "
                  "to generate PEEK" );
        compiler_push_error_type( cc, ex );
    }

}

static void compiler_compile_over( COMPILER *cc, cexception_t *ex )
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
	if( compiler_lookup_operator( cc, expr2_type, "over", 2, ex )) {
	    operator_description_t od;

	    compiler_init_operator_description( &od, cc, expr2_type,
                                                "over", 2, ex );
	    compiler_check_operator_args( cc, &od, generic_types, ex );
	    compiler_emit_operator_or_report_missing( cc, &od, NULL, "", ex );
	    compiler_check_operator_retvals( cc, &od, 1, 1 );
	    compiler_push_operator_retvals( cc, &od, NULL, generic_types,
                                            ex );
	    compiler_emit( cc, ex, "\n" );
	} else {
	    if( expr2_type ) {
		compiler_push_typed_expression( cc, expr2_type, ex );
		share_tnode( expr2_type );
                if( enode_has_flags( expr2, EF_IS_READONLY )) {
                    enode_set_flags( cc->e_stack, EF_IS_READONLY );
                }
	    } else {
                if( expr2 && !enode_has_flags( expr2, EF_HAS_ERRORS )) {
                    yyerrorf( "when generating OVER, second expression from the "
                              "stack top has no type (?!)" );
                }
	    }
	    compiler_emit( cc, ex, "\tc\n", OVER );
	}
    }
    cexception_catch {
	delete_typetab( generic_types );
	cexception_reraise( inner, ex );
    }
    delete_typetab( generic_types );
}

static int compiler_stack_top_has_operator( COMPILER *c,
                                            char *operator_name,
                                            int arity,
                                            cexception_t *ex )
{
    ENODE *expr_enode = c ? c->e_stack : NULL;
    TNODE *expr_tnode = expr_enode ? enode_type( expr_enode ) : NULL;

    if( !expr_tnode ) {
	return 0;
    }
    
    if( !compiler_lookup_operator( c, expr_tnode, operator_name, arity, ex )) {
	return 0;
    }

    return 1;
}

static int compiler_nth_stack_value_has_operator( COMPILER *c,
					       int number_from_top,
					       char *operator_name,
					       int arity,
                                               cexception_t *ex )
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

    if( !compiler_lookup_operator( c, expr_tnode, operator_name, arity, ex )) {
	return 0;
    }

    return 1;
}

static int compiler_variable_has_operator( COMPILER *c,
                                        DNODE *var_dnode,
					char *operator_name,
					int arity,
                                        cexception_t *ex )
{
    TNODE *var_tnode = NULL;
    DNODE *operator = NULL;

    if( ! var_dnode ) {
	return 0;
    }

    if( !( var_tnode = dnode_type( var_dnode ))) {
	return 0;
    }
    
    if( !( operator = compiler_lookup_operator( c, var_tnode, operator_name,
                                                arity, ex ))) {
	return 0;
    }

    return 1;
}

static void compiler_compile_jnz_or_jz( COMPILER *c,
				     ssize_t offset,
				     char *operator_name,
				     void *pointer_opcode,
				     void *number_opcode,
				     cexception_t *ex )
{
    ENODE * volatile top_enode = c->e_stack;
    TNODE * volatile top_tnode = top_enode ? enode_type( top_enode ) : NULL;

    if( compiler_lookup_operator( c, top_tnode, operator_name, 1, ex )) {
	compiler_check_and_compile_operator( c, top_tnode, operator_name,
					  /*arity:*/ 1,
					  /*fixup_values:*/ NULL, ex );
	compiler_emit( c, ex, "e\n", &offset );
    } else {
	if( tnode_is_reference( top_tnode )) {
	    compiler_emit( c, ex, "\tce\n", pointer_opcode, &offset );
	} else {
	    ssize_t zero = 0;
	    tnode_report_missing_operator( top_tnode, operator_name, 1 );
	    /* emit JMP instead of missing JNZ/JZ to avoid triggering
	       assertions later during backpatching: */
	    compiler_emit( c, ex, "\tce\n", JMP, &zero );
	}
	compiler_drop_top_expression( c );
    }
}

static void compiler_compile_jnz( COMPILER *c,
			       ssize_t offset,
			       cexception_t *ex )
{
    compiler_compile_jnz_or_jz( c, offset, "jnz", PJNZ, JNZ, ex );
}

static void compiler_compile_jz( COMPILER *c,
			      ssize_t offset,
			      cexception_t *ex )
{
    compiler_compile_jnz_or_jz( c, offset, "jz", PJZ, JZ, ex );
}

static void compiler_compile_loop( COMPILER *c,
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
	if( compiler_lookup_operator( c, limit_tnode, "loop", 2, ex )) {
	    compiler_check_and_compile_operator( c, limit_tnode, "loop",
					      /*arity:*/ 2,
					      /*fixup_values:*/ NULL, ex );
	    compiler_emit( c, ex, "e\n", &offset );
	} else {
	    tnode_report_missing_operator( limit_tnode, "loop", 2 );
	}
    }
}

static void compiler_compile_next( COMPILER *c,
                                   ssize_t offset,
                                   cexception_t *ex )
{
    ssize_t ncounters, i;

    /* stack: ..., current_ptr */
    ENODE * volatile counter_enode = c->e_stack;
    TNODE * volatile counter_tnode = counter_enode ?
	enode_type( counter_enode ) : NULL;

    if( !counter_enode ) {
	yyerrorf( "too little values on the eval stack for NEXT operator" );
    }

    if( counter_tnode ) {
	if( compiler_lookup_operator( c, counter_tnode, "next", 1, ex )) {
	    compiler_check_and_compile_operator( c, counter_tnode, "next",
                                                 /*arity:*/ 1,
                                                 /*fixup_values:*/ NULL, ex );
	    compiler_emit( c, ex, "e\n", &offset );
	} else {
	    tnode_report_missing_operator( counter_tnode, "next", 1 );
	}
    }

    /* One loop counter is removed by the "next" operator; the rest
       must be dropped explicitly: */
    ncounters = dnode_loop_counters( c->loops ) - 1;
    if( ncounters > 0 ) {
        if( ncounters == 1 ) {
            compiler_emit( c, ex, "\tc\n", PDROP );
        } else {
            compiler_emit( c, ex, "\tce\n", PDROPN, &ncounters );
        }
    }
    for( i = 0; i < ncounters; i ++ ) {
        compiler_drop_top_expression( c );
    }
}

static void compiler_compile_alloc( COMPILER *cc,
                                    TNODE *alloc_type,
                                    cexception_t *ex )
{
    compiler_push_typed_expression( cc, alloc_type, ex );
    if( !tnode_is_reference( alloc_type )) {
	yyerrorf( "only reference-implemented types can be "
		  "used in new operator" );
    }
    if( tnode_kind( alloc_type ) == TK_ARRAY ) {
	yyerrorf( "arrays should be allocated with array-new operator "
		  "(e.g. 'a = new int[20]')" );
    }

    if ( compiler_lookup_operator( cc, alloc_type, "new",
                                   /* arity = */ 0, ex )) {
        key_value_t *fixup_values =
            make_tnode_key_value_list( alloc_type, NULL );

	compiler_check_and_compile_operator( cc, alloc_type, "new",
                                             /* arity = */ 0, 
                                             fixup_values, ex );
    } else {
	ssize_t alloc_size = tnode_size( alloc_type );
	ssize_t alloc_nref = tnode_number_of_references( alloc_type );
	ssize_t vmt_offset = tnode_vmt_offset( alloc_type );

	if( vmt_offset == 0 ) {
	    compiler_emit( cc, ex, "\tcee\n", ALLOC, &alloc_size, &alloc_nref );
	} else {
	    compiler_emit( cc, ex, "\tceee\n", ALLOCVMT, &alloc_size, &alloc_nref,
			&vmt_offset );
	}
    }
}

static char *compiler_make_typed_operator_name( TNODE *index_type1,
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

static char* compiler_indexing_operator_name( TNODE *index_type,
                                              cexception_t *ex )
{
    return compiler_make_typed_operator_name( index_type, NULL, "[%s]", ex );
}

static void compiler_compile_composite_alloc_operator( COMPILER *cc,
                                                       TNODE *composite_type,
                                                       key_value_t *fixup_values,
                                                       cexception_t *ex )
{
    ENODE *volatile top_expr = cc->e_stack;
    TNODE *volatile top_type = top_expr ? enode_type( top_expr ) : NULL;
    const int arity = 1;
    char *operator_name;

    operator_name =
        compiler_make_typed_operator_name( top_type, NULL, "new[%s]", ex );

    if( compiler_lookup_operator( cc, composite_type, operator_name,
                                  arity, ex )) {
	compiler_check_and_compile_operator( cc, composite_type, operator_name,
					  arity, fixup_values, ex );
	/* Return value pushed by ..._compile_operator() function must
	   be dropped, since it only describes return value as having
	   type 'composite'. The caller of the current function will push
	   a correct return value 'composite of proper_element_type' */
	compiler_drop_top_expression( cc );
    } else {
	compiler_check_and_remove_index_type( cc );
	tnode_report_missing_operator( composite_type, operator_name, arity );
    }
}

static void compiler_compile_composite_alloc( COMPILER *cc,
                                              TNODE *composite_type,
                                              TNODE *element_type,
                                              cexception_t *ex )
{
    TNODE *allocated_type = NULL;
    key_value_t *fixup_values = 
        make_tnode_key_value_list( composite_type, element_type );

    allocated_type = new_tnode_composite_synonim( composite_type, element_type,
						  ex );

    compiler_compile_composite_alloc_operator( cc, allocated_type,
					    fixup_values, ex );

    compiler_push_typed_expression( cc, allocated_type, ex );
    /* compiler_push_composite_of_type( cc, composite_type, element_type, ex ); */
}

static void compiler_compile_array_alloc_operator( COMPILER *cc,
                                                   char *operator_name,
                                                   key_value_t *fixup_values,
                                                   cexception_t *ex )
{
    ENODE *volatile top_expr = cc->e_stack;
    TNODE *volatile top_type = top_expr ? enode_type( top_expr ) : NULL;
    const int arity = 1;

    if( compiler_stack_top_has_operator( cc, operator_name, arity, ex )) {
	compiler_check_and_compile_operator( cc, top_type, operator_name,
					  arity, fixup_values, ex );
	/* Return value pushed by ..._compile_operator() function must
	   be dropped, since it only describes return value as having
	   type 'array'. The caller of the current function will push
	   a correct return value 'array of proper_element_type' */
	compiler_drop_top_expression( cc );
        compiler_emit( cc, ex, "\n" );
    } else {
	compiler_check_and_remove_index_type( cc );
	tnode_report_missing_operator( top_type, operator_name, arity );
    }
}

static void compiler_compile_array_alloc( COMPILER *cc,
                                          TNODE *element_type,
                                          cexception_t *ex )
{
    key_value_t *fixup_values = make_tnode_key_value_list( NULL, element_type );

    if( element_type && tnode_kind( element_type ) != TK_PLACEHOLDER ) {
        compiler_compile_array_alloc_operator( cc, "new[]", fixup_values, ex );
    } else {
        if( element_type ) {
            yyerrorf( "in this type representation, can not allocate array "
                      "of generic type %s", tnode_name( element_type ));
        } else {
            yyerrorf( "undefined element type for array allocation" );
        }
    }
    compiler_push_array_of_type( cc, element_type, ex );
}

static void compiler_compile_blob_alloc( COMPILER *cc,
				      cexception_t *ex )
{
    static key_value_t fixup_values[] = {
	{ "element_nref", 0 },
	{ "element_size", 1 },
	{ NULL },
    };

    compiler_compile_array_alloc_operator( cc, "blob[]", fixup_values, ex );
    compiler_push_typed_expression( cc, new_tnode_blob_snail( cc->typetab, ex ), ex );
}

static void compiler_compile_mdalloc( COMPILER *cc,
				   TNODE *element_type,
				   int level,
				   cexception_t *ex )
{
    TNODE *array_tnode = new_tnode_array_snail( NULL, cc->typetab, ex );

    if( element_type ) {
	key_value_t *fixup_values =
	    make_mdalloc_key_value_list( element_type, level );

	compiler_compile_array_alloc_operator( cc, "new[][]", fixup_values, ex );
	compiler_append_expression_type( cc, array_tnode );
	compiler_append_expression_type( cc, share_tnode( element_type ));
    } else {
	key_value_t fixup_vals[] = {
	    { "element_size", sizeof(void*) },
	    { "element_nref", 1 },
	    { "element_align", sizeof(void*) },
	    { "level", level },
	    { NULL }
	};

	if( level == 0 ) {
	    compiler_compile_array_alloc_operator( cc, "new[]", fixup_vals, ex );
	    compiler_push_typed_expression( cc, array_tnode, ex );
	} else {
	    compiler_compile_array_alloc_operator( cc, "new[][]", fixup_vals, ex );
	    compiler_append_expression_type( cc, array_tnode );
	}
    }
}

static void compiler_begin_scope( COMPILER *c,
                                  cexception_t *ex )
{
    assert( c );
    assert( c->vartab );

    push_ssize_t( &c->local_offset_stack, &c->local_offset_stack_size,
                  c->local_offset, ex );
    c->local_offset = starting_local_offset;
    vartab_begin_scope( c->vartab, ex );
    vartab_begin_scope( c->consts, ex );
    vartab_begin_scope( c->operators, ex );

    typetab_begin_scope( c->typetab, ex );
}

static void compiler_end_scope( COMPILER *c, cexception_t *ex )
{
    assert( c );
    assert( c->vartab );

    c->local_offset = pop_ssize_t( &c->local_offset_stack,
                                   &c->local_offset_stack_size, ex );
    vartab_end_scope( c->consts, ex );
    vartab_end_scope( c->vartab, ex );
    vartab_end_scope( c->operators, ex );

    typetab_end_scope( c->typetab, ex );
}

static void compiler_begin_subscope( COMPILER *c,
                                     cexception_t *ex )
{
    assert( c );
    assert( c->vartab );

    vartab_begin_subscope( c->vartab, ex );
    vartab_begin_subscope( c->consts, ex );
    vartab_begin_subscope( c->operators, ex );
    typetab_begin_subscope( c->typetab, ex );
}

static void compiler_end_subscope( COMPILER *c, cexception_t *ex )
{
    assert( c );
    assert( c->vartab );

    vartab_end_subscope( c->consts, ex );
    vartab_end_subscope( c->vartab, ex );
    vartab_end_subscope( c->operators, ex );
    typetab_end_subscope( c->typetab, ex );
}

static void compiler_push_guarding_arg( COMPILER *cc, cexception_t *ex )
{
    ENODE *arg = new_enode_guarding_arg( ex );
    enode_list_push( &cc->e_stack, arg );
}

static void compiler_push_guarding_retval( COMPILER *cc, cexception_t *ex )
{
    ENODE *arg = new_enode_guarding_arg( ex );
    enode_set_flags( arg, EF_RETURN_VALUE );
    enode_list_push( &cc->e_stack, arg );
}

static DNODE* compiler_lookup_dnode_silently( COMPILER *cc,
                                              DNODE *module,
                                              char *identifier )
{
    if( !module ) {
	return vartab_lookup( cc->vartab, identifier );
    } else {
        if( dnode_vartab( module ) != NULL ) {
            return dnode_vartab_lookup_var( module, identifier );
        } else {
            return NULL;
        }
    }
}

static DNODE* compiler_lookup_dnode( COMPILER *cc,
                                     DNODE *module,
                                     char *identifier,
                                     char *message )
{
    DNODE *varnode =
	compiler_lookup_dnode_silently( cc, module, identifier );

    if( !varnode ) {
        char *module_name = module ? dnode_name( module ) : NULL;
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

/*
  Function compiler_push_varaddr_expr() pushes a fake expression with
  variable reference onto the stack. It is fake because no code is
  generated to push this "address". Instead, code emitter will emit
  'ST %variable' when encountered such expression.

  In principle, assignement to variables could be implemented as 'LDA
  %variable; compute_value; STI', but the scheme with fake variable
  references produces more efficient code 'compute_value; ST
  %variable'.
*/

static void compiler_push_varaddr_expr( COMPILER *cc,
                                        char *variable_name,
                                        cexception_t *ex )
{
    DNODE *var_dnode = compiler_lookup_dnode( cc, NULL /* module_name */,
                                              variable_name, "variable" );
    ENODE *arg = var_dnode ?
        new_enode_varaddr_expr( var_dnode, ex ) : NULL;
    if( arg ) {
        share_dnode( var_dnode );
        enode_list_push( &cc->e_stack, arg );
    } else {
        compiler_push_error_type( cc, ex );
    }
}

static type_kind_t compiler_stack_top_type_kind( COMPILER *cc )
{
    ENODE *top_expr = cc->e_stack;
    TNODE *top_type = top_expr ? enode_type( cc->e_stack ) : NULL;

    if( top_type ) {
	return tnode_kind( top_type );
    } else {
	return TK_NONE;
    }
}

static void compiler_make_stack_top_element_type( COMPILER *cc )
{
    if( cc->e_stack ) {
	enode_make_type_to_element_type( cc->e_stack );
    } else {
	yyerror( "not enough values on the evaluation stack for "
		 "taking base type?" );
    }
}

static DNODE* compiler_make_stack_top_field_type( COMPILER *cc,
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
	    enode_replace_type( cc->e_stack,
                                share_tnode( dnode_type( field )));
            if( field && dnode_has_flags( field, DF_IS_READONLY )) {
                enode_set_flags( cc->e_stack, EF_IS_READONLY );
            }
	}
	return field;
    } else {
	yyerror( "not enough values on the evaluation stack for "
		 "taking base type?" );
	return NULL;
    }
}

static void compiler_make_stack_top_addressof( COMPILER *cc,
					    cexception_t *ex )
{
    if( cc->e_stack ) {
	enode_make_type_to_addressof( cc->e_stack, ex );
    } else {
	yyerror( "not enough values on the evaluation stack for "
		 "taking address?" );
    }    
}

static void compiler_check_and_drop_function_args( COMPILER *cc,
                                                   DNODE *function,
                                                   TYPETAB *generic_types,
                                                   cexception_t *ex )
{
    DNODE *function_args = dnode_function_args( function );
    DNODE *formal_arg = NULL;
    TNODE *formal_type, *actual_type;
    ssize_t n = 0;
    ssize_t nargs = dnode_list_length( function_args );

    foreach_reverse_dnode( formal_arg, function_args ) {
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
            char msg[300] = "";
            if( !tnode_types_are_assignment_compatible
                ( formal_type, actual_type, generic_types,
                  msg, sizeof(msg), ex )) {
                if( msg[0] ) {
                    yyerrorf( "incompatible types for function '%s' argument "
                              "nr. %d - %s", dnode_name( function ),
                              nargs - n, /* dnode_name( formal_arg ),  */msg );
                } else {
                    yyerrorf( "incompatible types for function '%s' argument "
                              "nr. %d"/* " (%s)" */, dnode_name( function ),
                              nargs - n, dnode_name( formal_arg ));
                }
            }
            if( !enode_is_readonly_compatible_for_param( actual_arg,
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

static DNODE *compiler_check_and_set_fn_proto( COMPILER *cc,
                                               DNODE *fn_proto,
                                               cexception_t *ex )
{
    DNODE *fn_dnode = NULL;
    TNODE *fn_tnode = NULL;
    int count = 0, is_imported = 0;
    char msg[100];

    fn_dnode = vartab_lookup_silently( cc->vartab, dnode_name( fn_proto ),
                                       &count, &is_imported );
    if( fn_dnode && !is_imported ) {
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
        DNODE *volatile shared_proto = share_dnode( fn_proto );
        cexception_t inner;
        cexception_guard( inner ) {
            compiler_vartab_insert_single_named_var( cc, &shared_proto, &inner );
        }
        cexception_catch {
            delete_dnode( shared_proto );
            cexception_reraise( inner, ex );
        }
	return fn_proto;
    }
}

static DNODE *compiler_check_and_set_constructor( TNODE *class_tnode,
                                                  DNODE *fn_proto,
                                                  cexception_t *ex )
{
    DNODE *fn_dnode = NULL;
    TNODE *fn_tnode = NULL;
    char msg[100];

    assert( class_tnode );

    fn_dnode = tnode_lookup_constructor( class_tnode, dnode_name( fn_proto ));

    if( fn_dnode ) {
	fn_tnode = dnode_type( fn_dnode );
	if( !dnode_is_function_prototype( fn_dnode )) {
            char *constructor_name = dnode_name( fn_proto );
            if( constructor_name && *constructor_name ) {
                yyerrorf( "constructor '%s' is already declared in this scope",
                          constructor_name );
            } else {
                yyerrorf( "default constructor is already declared in this scope",
                          constructor_name );
            }
	} else
	if( !tnode_function_prototypes_match_msg( fn_tnode,
					          dnode_type( fn_proto ),
					          msg, sizeof( msg ))) {
	    yyerrorf( "prototype of constructor %s() does not match "
		      "previous definition - %s", dnode_name( fn_proto ),
		      msg );
	}
        if( fn_dnode != fn_proto ) {
            dnode_shallow_copy( fn_dnode, fn_proto, ex );
        }
	delete_dnode( fn_proto );
	return fn_dnode;
    } else {
	tnode_insert_constructor( class_tnode, share_dnode( fn_proto ));
	return fn_proto;
    }
}

static void compiler_emit_argument_list( COMPILER *cc,
                                         DNODE *argument_list,
                                         cexception_t *ex )
{
    DNODE *varnode;
    DNODE *volatile shared_varnode = NULL;

    cexception_t inner;
    cexception_guard( inner ) {
        foreach_reverse_dnode( varnode, argument_list ) {
            TNODE *argtype = dnode_type( varnode );

            dnode_assign_offset( varnode, &cc->local_offset );
            shared_varnode = share_dnode( varnode );
            vartab_insert_named( cc->vartab, &shared_varnode, &inner );

            compiler_emit_st( cc, argtype, dnode_name( varnode ),
                              dnode_offset( varnode ), dnode_scope( varnode ),
                              &inner );
        }
    }
    cexception_catch {
        delete_dnode( shared_varnode );
        cexception_reraise( inner, ex );
    }
}

static void compiler_emit_function_arguments( DNODE *function, COMPILER *cc,
                                              cexception_t *ex )
{
    assert( function );
    compiler_emit_argument_list( cc, dnode_function_args( function ), ex );
}

static void compiler_emit_drop_returned_values( COMPILER *cc,
                                                ssize_t drop_retvals,
                                                cexception_t *ex  )
{
    if( drop_retvals > 1 ) {
	compiler_compile_dropn( cc, drop_retvals, ex );
    } else if( drop_retvals == 1 ) {
	compiler_compile_drop( cc, ex );
    }    
}

static TNODE *compiler_lookup_suffix_tnode( COMPILER *cc,
                                            type_suffix_t suffix_type,
                                            DNODE *module,
                                            char *suffix,
                                            char *constant_kind_name )
{
    TNODE *const_type = NULL;

    if( module ) {
        const_type =
            dnode_typetab_lookup_suffix( module, suffix ? suffix : "",
                                         suffix_type );
        if( !const_type ) {
            const_type =
                dnode_typetab_lookup_type( module, suffix ? suffix : "" );
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

static void compiler_compile_enum_const_from_tnode( COMPILER *cc,
                                                    char *value_name,
                                                    TNODE *const_type,
                                                    cexception_t *ex )
{
    DNODE *const_dnode = const_type ?
	tnode_lookup_field( const_type, value_name ) : NULL;
    ssize_t string_offset = const_dnode ?
	dnode_offset( const_dnode ) : 0;

    if( !const_type ) {
	compiler_push_error_type( cc, ex );
	return;
    }

    if( compiler_lookup_operator( cc, const_type, "ldc", 0, ex ) != NULL ) {
	compiler_compile_operator( cc, const_type, "ldc", 0, ex );
    } else {
	compiler_push_typed_expression( cc, const_type, ex );
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

	    snprintf( value_str, sizeof(value_str), "%ld", (long)value );
	    string_offset =
		compiler_assemble_static_string( cc, value_str, ex );
	    dnode_set_offset( const_dnode, string_offset );
	}
    }

    compiler_emit( cc, ex, "e\n", &string_offset );
}

static TNODE* compiler_lookup_tnode_with_function( COMPILER *cc,
                                                   DNODE *module,
                                                   char *identifier,
                                                   TNODE* (*typetab_lookup_fn)
                                                   (TYPETAB*,const char*))
{
    if( !module ) {
	return (*typetab_lookup_fn)( cc->typetab, identifier );
    } else {
        return dnode_typetab_lookup_type( module, identifier );
    }
}

static TNODE* compiler_lookup_tnode_silently( COMPILER *cc,
                                              DNODE *module,
                                              char *identifier )
{
    return compiler_lookup_tnode_with_function( cc, module,
                                                identifier,
                                                typetab_lookup_silently );
}

static TNODE* compiler_lookup_tnode( COMPILER *cc,
                                     DNODE *module,
                                     char *identifier,
                                     char *message )
{
    TNODE *typenode = compiler_lookup_tnode_with_function( cc, module,
                                                           identifier,
                                                           typetab_lookup );

    if( !typenode ) {
        char *module_name = module ? dnode_name( module ) : NULL;
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

static void compiler_compile_enumeration_constant( COMPILER *cc,
                                                   DNODE *module,
                                                   char *value_name,
                                                   char *type_name,
                                                   cexception_t *ex )
{
    TNODE *const_type =
	compiler_lookup_tnode( cc, module, type_name, "enumeration type" );

    compiler_compile_enum_const_from_tnode( cc, value_name, const_type, ex );
}

static void compiler_compile_typed_constant( COMPILER *cc,
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
		    compiler_compile_enum_const_from_tnode( cc, enum_value_name,
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

	if( compiler_lookup_operator( cc, const_type, "ldc", 0, ex ) != NULL ) {
	    compiler_compile_operator( cc, const_type, "ldc", 0, ex );
	} else {
	    compiler_push_typed_expression( cc, const_type, ex );
	    share_tnode( const_type );
	    tnode_report_missing_operator( const_type, "ldc", 0 );
	}
        ENODE *expr = cc->e_stack;
        assert( expr );
        enode_set_flags( expr, EF_IS_CONSTANT );
        if( strcmp( value, "0" ) == 0 ) {
            enode_set_flags( expr, EF_IS_ZERO );
        }
	string_offset = compiler_assemble_static_string( cc, value, ex );
	compiler_emit( cc, ex, "e\n", &string_offset );
    }
}

static void compiler_compile_constant( COMPILER *cc,
                                       type_suffix_t suffix_type,
                                       DNODE *module,
                                       char *suffix, char *constant_kind_name,
                                       char *value,
                                       cexception_t *ex )
{
    TNODE *const_type =
	compiler_lookup_suffix_tnode( cc, suffix_type, module,
                                      suffix, constant_kind_name );

    compiler_compile_typed_constant( cc, const_type, value, ex );
}

static DNODE* compiler_lookup_constant( COMPILER *cc,
                                        DNODE *module,
                                        char *identifier,
                                        char *message )
{
    DNODE *constnode;

    if( !module ) {
	constnode = vartab_lookup( cc->consts, identifier );
    } else {
        constnode = dnode_consttab_lookup_const( module, identifier );
    }
    if( !constnode ) {
        char *module_name = module ? dnode_name( module ) : NULL;
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

static void compiler_compile_ld( COMPILER *cc,
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
	operator =
            compiler_lookup_operator( cc, var_type, operator_name, arity, ex );

	cexception_guard( inner ) {
	    if( tnode_creator ) {
		expr_type = tnode_creator( var_type, &inner );
	    } else {
		expr_type = var_type;
	    }
	    share_tnode( var_type );
	    compiler_push_typed_expression( cc, expr_type, &inner );
	    if( dnode_has_flags( varnode, DF_IS_READONLY )) {
		enode_set_flags( cc->e_stack, EF_IS_READONLY );
	    }
	}
	cexception_catch {
	    delete_tnode( expr_type );
	    cexception_reraise( inner, ex );
	}

	if( operator ) {
	    compiler_emit_function_call( cc, operator, NULL, "", ex );
	} else {
	    if( fallback_opcode == LDA ) {
		if( dnode_scope( varnode ) == compiler_current_scope( cc )) {
		    if( tnode_is_reference( var_type )) {
			compiler_emit( cc, ex, "\tc", PLDA );
		    } else {
			compiler_emit( cc, ex, "\tc", LDA );
		    }
		} else {
		    if( dnode_scope( varnode ) == 0 ) {
			operator = compiler_lookup_operator( cc, var_type,
                                                             "ldga",
                                                             arity, ex );
			if( operator ) {
			    compiler_emit_function_call( cc, operator, NULL,
						      "", ex );
			} else {
			    if( tnode_is_reference( var_type )) {
				compiler_emit( cc, ex, "\tc", PLDGA );
			    } else {
				compiler_emit( cc, ex, "\tc", LDGA );
			    }
			}
		    } else {
			yyerrorf( "can only fetch variables either from the "
				  "current scope of from the scope 0" );
		    }
		}
	    } else if( fallback_opcode == LD ) {
		if( dnode_scope( varnode ) == compiler_current_scope( cc )) {
		    if( tnode_is_reference( var_type )) {
			compiler_emit( cc, ex, "\tc", PLD );
		    } else {
			compiler_emit( cc, ex, "\tc", LD );
		    }
		} else {
		    if( dnode_scope( varnode ) == 0 ) {
			operator = compiler_lookup_operator( cc, var_type,
                                                             "ldg",
                                                             arity, ex );
			if( operator ) {
			    compiler_emit_function_call( cc, operator, NULL,
						      "", ex );
			} else {
			    if( tnode_is_reference( var_type )) {
				compiler_emit( cc, ex, "\tc", PLDG );
			    } else {
				compiler_emit( cc, ex, "\tc", LDG );
			    }
			}
		    } else {
			yyerrorf( "can only fetch variable addressess either "
				  "from the current scope of from "
				  "the scope 0" );
		    }
		}
	    } else {
		compiler_emit( cc, ex, "\tc", fallback_opcode );
	    }
	}
	varnode_offset = dnode_offset( varnode );
	compiler_emit( cc, ex, "eN\n", &varnode_offset, dnode_name( varnode ));
    } else {
	/* yyerrorf( "name '%s' not declared in the current scope",
	   identifier ); */
	compiler_emit( cc, ex, "\tcNN\n", operator, "???", "???" );
	compiler_push_error_type( cc, ex );
    }
}

static void compiler_compile_load_variable_value( COMPILER *cc,
                                                  DNODE *varnode,
                                                  cexception_t *ex )
{
    compiler_compile_ld( cc, varnode, "ld", LD, NULL, ex );
}

static void compiler_compile_load_function_address( COMPILER *cc,
                                                    DNODE *varnode,
                                                    cexception_t *ex )
{
    compiler_compile_ld( cc, varnode, "ldfn", LDFN, NULL, ex );
}

static void compiler_compile_load_variable_address( COMPILER *cc,
                                                    DNODE *varnode,
                                                    cexception_t *ex )
{
    compiler_compile_ld( cc, varnode, "lda", LDA, new_tnode_addressof, ex );
}

static void compiler_fixup_function_calls( THRCODE *tc, DNODE *funct )
{
    char *name;
    int address;

    assert( funct );
    name = dnode_name( funct );
    address = dnode_offset( funct );

    thrcode_fixup_function_calls( tc, name, address );
}

static void compiler_compile_function_thrcode( COMPILER *cc )
{
    assert( cc );
    assert( cc->thrcode != cc->function_thrcode );
    delete_thrcode( cc->thrcode );
    cc->thrcode = share_thrcode( cc->function_thrcode );
}

static void compiler_compile_main_thrcode( COMPILER *cc )
{
    assert( cc );
    assert( cc->thrcode != cc->main_thrcode );
    delete_thrcode( cc->thrcode );
    cc->thrcode = share_thrcode( cc->main_thrcode );
}

static void compiler_merge_functions_and_main( COMPILER *cc,
                                               cexception_t *ex  )
{
    assert( cc );
    thrcode_merge( cc->function_thrcode, cc->main_thrcode, ex );
    delete_thrcode( cc->main_thrcode );
    cc->main_thrcode = cc->function_thrcode;
    cc->function_thrcode = NULL;
    delete_thrcode( cc->thrcode );
    cc->thrcode = share_thrcode( cc->main_thrcode );
}

static void compiler_push_thrcode( COMPILER *sc,
                                   cexception_t *ex )
{
    thrlist_push_data( &sc->thrstack, &sc->thrcode, delete_thrcode, NULL, ex );
    create_thrcode( &sc->thrcode, ex );
    elist_push_data( &sc->saved_estacks, &sc->e_stack, delete_enode, NULL, ex );
    sc->e_stack = NULL;
}

static void compiler_swap_thrcodes( COMPILER *sc )
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

static void compiler_merge_top_thrcodes( COMPILER *sc, cexception_t *ex )
{
    thrcode_merge( sc->thrcode, thrlist_data( sc->thrstack ), ex );
    thrlist_drop( &sc->thrstack );
    sc->e_stack = 
	enode_append( elist_pop_data( &sc->saved_estacks ), sc->e_stack );
}

static void compiler_merge_functions_and_top( COMPILER *cc,
                                              cexception_t *ex )
{
    assert( cc );
    assert( cc->function_thrcode != cc->thrcode );
    assert( cc->function_thrcode != cc->main_thrcode );

    thrcode_merge( cc->function_thrcode, cc->thrcode, ex );

    delete_thrcode( cc->thrcode );

    cc->thrcode = thrlist_pop_data( &cc->thrstack );

    /* Actually, after function compilation the e-stack of the
       finished function should be empty, so in fact the following
       code should instead be an assert()... S.G. */
    cc->e_stack = 
	enode_append( elist_pop_data( &cc->saved_estacks ), cc->e_stack );
}

static void compiler_get_inline_code( COMPILER *cc,
                                      DNODE *function,
                                      cexception_t *ex )
{
    ssize_t code_start = compiler_pop_address( cc, ex );
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

static int compiler_count_return_values( DNODE *funct )
{
    TNODE *function_type = funct ? dnode_type( funct ) : NULL;
    DNODE *retvals = function_type ? tnode_retvals( function_type ) : NULL;

    return dnode_list_length( retvals );
}

static void compiler_compile_address_of_indexed_element( COMPILER *cc,
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
	idx_name = compiler_indexing_operator_name( index_type, &inner );

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

	if( compiler_lookup_operator( cc, array_type, idx_name,
                                      idx_arity, ex )) {
	    compiler_init_operator_description( &od, cc, array_type, idx_name,
                                                idx_arity, ex );
	} else {
	    compiler_init_operator_description( &od, cc, index_type, "[]",
                                                idx_arity, ex );
	}

	if( od.operator ) {
	    compiler_check_operator_args( cc, &od, generic_types,
                                          &inner );
	}

	index_expr = enode_list_pop( &cc->e_stack );

	if( od.operator ) {
	    TNODE *return_type = NULL;
	    key_value_t *fixup_values = NULL;

	    array_expr = cc->e_stack;

	    fixup_values = make_tnode_key_value_list( array_type, NULL );

	    compiler_emit_operator_or_report_missing( cc, &od, fixup_values,
                                                      "", &inner );

	    compiler_check_operator_retvals( cc, &od, 1, 1 );
	    return_type = od.retvals ? dnode_type( od.retvals ) : NULL;

	    if( return_type ) {
		if( tnode_kind( return_type ) == TK_ADDRESSOF &&
		    tnode_element_type( return_type ) == NULL ) {
		    if( !element_type ) {
			yyerrorf( "can not index array with unknown element "
				  "type" );
		    }
		    if( compiler_stack_top_type_kind( cc ) ==  TK_ADDRESSOF ) {
			compiler_make_stack_top_element_type( cc );
		    }
		    compiler_make_stack_top_element_type( cc );
		    compiler_make_stack_top_addressof( cc, &inner );
		} else {
		    enode_list_drop( &cc->e_stack );
		    compiler_push_typed_expression( cc, return_type, &inner );
		    share_tnode( return_type );
		}
	    }
	    compiler_emit( cc, &inner, "\n" );
	} else {
	    compiler_make_stack_top_element_type( cc );
	    compiler_make_stack_top_addressof( cc, &inner );
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

static void compiler_compile_subarray( COMPILER *cc,
                                       cexception_t *ex )
{
    cexception_t inner;
    ENODE * volatile index_expr1 = NULL;
    ENODE * volatile index_expr2 = NULL;
    ENODE * volatile array_expr = NULL;
    TNODE *index_type1 = NULL;
    TNODE *index_type2 = NULL;
    TNODE *array_type = NULL;
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
            ( ex, COMPILER_UNRECOVERABLE_ERROR,
              "subarray index range expressions were not generated properly" );
    }
    /* From now on, index_expr1 and index_expr2 are not NULL */

    cexception_guard( inner ) {
        generic_types = new_typetab( &inner );
        idx_name = compiler_make_typed_operator_name( index_type1, index_type2,
                                                   "[%s..%s]", ex );

	if( array_expr ) {
	    array_type = enode_type( array_expr );
	    if( array_type && tnode_kind( array_type ) == TK_ADDRESSOF ) {
		array_type = tnode_element_type( array_type );
	    }
	}

	if( !array_type ) {
	    yyerrorf( "not enough values on the stack "
                      "for a subarray/substring operator" );
	}

	if( compiler_lookup_operator( cc, array_type, idx_name,
                                      idx_arity, &inner )) {
	    compiler_init_operator_description( &od, cc, array_type, idx_name,
                                                idx_arity, &inner );
	} else if( tnode_lookup_operator( index_type1, idx_name, idx_arity )) {
	    compiler_init_operator_description( &od, cc, index_type1, "[..]",
                                                idx_arity, &inner );
	} else {
            compiler_init_operator_description( &od, cc, index_type2, "[..]",
                                                idx_arity, &inner );
        }

	if( od.operator ) {
	    compiler_check_operator_args( cc, &od, generic_types,
                                          &inner );
	}

	index_expr1 = enode_list_pop( &cc->e_stack );
	index_expr2 = enode_list_pop( &cc->e_stack );

	if( od.operator ) {
	    TNODE *return_type = NULL;
	    key_value_t *fixup_values = NULL;

	    array_expr = cc->e_stack;

	    fixup_values = make_tnode_key_value_list( array_type, NULL );

	    compiler_emit_operator_or_report_missing( cc, &od, fixup_values,
                                                      "", &inner );

	    compiler_check_operator_retvals( cc, &od, 1, 1 );
	    return_type = od.retvals ? dnode_type( od.retvals ) : NULL;

	    if( return_type ) {
		assert( tnode_kind( return_type ) != TK_ADDRESSOF );
                if( tnode_kind( return_type ) == TK_ARRAY &&
                    tnode_element_type( return_type )) {
                    enode_list_drop( &cc->e_stack );
                    compiler_push_typed_expression( cc, return_type, &inner );
                    share_tnode( return_type );
                }
	    }
	    compiler_emit( cc, &inner, "\n" );
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

static void compiler_compile_indexing( COMPILER *cc,
                                       int array_is_reference,
                                       int expr_count,
                                       cexception_t *ex )
{
    if( expr_count == 1 ) {
	compiler_compile_address_of_indexed_element( cc, ex );
    } else if( expr_count == 0 ) {
	if( !array_is_reference ) {
            yyerrorf( "only references sould be cloned with '[]' operator" );
        }
        compiler_emit( cc, ex, "\tc\n", CLONE );
        if( cc->e_stack ) {
            enode_reset_flags( cc->e_stack, EF_IS_READONLY );
        }
    } else if( expr_count == -1 ) {
        TNODE *top_type = cc->e_stack ? enode_type( cc->e_stack ) : NULL;
        compiler_compile_over( cc, ex );
        compiler_check_and_compile_operator( cc, top_type, "last", 1,
                                             /* fixups = */ NULL, ex );
        compiler_compile_subarray( cc, ex );
    } else if( expr_count == 2 ) {
        compiler_compile_subarray( cc, ex );
    } else {
	assert( 0 );
    }
}

static void compiler_compile_type_declaration( COMPILER *cc,
                                               TNODE *type_descr,
                                               cexception_t *ex )
{
    cexception_t inner;
    TNODE *volatile tnode = NULL;
    char * volatile type_name = NULL;

    if( !type_descr ) {
	/* cc->current_type = NULL; */
        delete_tnode( compiler_pop_current_type( cc ));
        return;
    }

    type_name = strdupx( tnode_name( cc->current_type ), ex );

    cexception_guard( inner ) {
	assert( type_descr );
	if( tnode_name( type_descr ) == NULL ) {
	    tnode = tnode_set_name( type_descr, type_name, &inner );
	} else if( type_descr != cc->current_type ) {
	    tnode = tnode_set_name( new_tnode_equivalent( type_descr, &inner ),
				    type_name, &inner );
            tnode_set_suffix( tnode, tnode_name( tnode ), &inner );
            delete_tnode( type_descr );
	} else {
	    tnode = type_descr;
	}
        type_descr = NULL;
	compiler_typetab_insert( cc, &tnode, &inner );
	tnode = typetab_lookup_silently( cc->typetab, type_name );
	tnode_reset_flags( tnode, TF_IS_FORWARD );
        share_tnode( tnode );
	compiler_insert_tnode_into_suffix_list( cc, tnode, &inner );
        tnode = NULL;
	/* cc->current_type = NULL; */
        delete_tnode( compiler_pop_current_type( cc ));
	freex( type_name );
    }
    cexception_catch {
	freex( type_name );
        delete_tnode( tnode );
	cexception_reraise( inner, ex );
    }
    assert( !tnode );
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
	return 0;
    } 
}

static int compiler_check_and_emit_program_arguments( COMPILER *cc,
						      DNODE *args,
						      cexception_t *ex )
{
    DNODE *arg;
    int n = 1;
    int retval = 1;

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
                compiler_emit( cc, ex, "\tcI\n", LDC, 0 );
                compiler_emit( cc, ex, "\tcI\n", LDC, -1 );
		compiler_emit( cc, ex, "\tcT\n", ALLOCARGV, "(* argv *)" );
	    } else {
		compiler_emit( cc, ex, "\tcT\n", ALLOCENV, "(* env *)" );
	    }
	    break;
	case 2:
	    if( !tnode_is_array_of_file( arg_type )) {
		yyerrorf( "argument nr. %d of the program must be "
			  "'array of file'", n );
		retval = 0;
	    }
	    compiler_emit( cc, ex, "\tcT\n", ALLOCSTDIO, "(* stdio *)" );
	    break;
	}
	n++;
    }
    if( --n > 3 ) {
	yyerrorf( "too many arguments for the program "
		  "(found %d, must be <= 3)", n );
	retval = 0;
    }
    return retval;
}

static void compiler_emit_catch_comparison( COMPILER *cc,
                                            DNODE *module,
                                            char *exception_name,
                                            cexception_t *ex )
{
    DNODE *exception =
        compiler_lookup_dnode( cc, module, exception_name, "exception" );
    ssize_t zero = 0;
    ssize_t exception_val;
    ssize_t try_var_offset = cc->try_variable_stack ?
	cc->try_variable_stack[cc->try_block_level-1] : 0;

    if( module ) {
        char *module_name = module ? dnode_name( module ) : NULL;
	compiler_emit( cc, ex, "\n\tce\n", PLD, &try_var_offset );
	compiler_emit( cc, ex, "\n\tc\n", EXCEPTIONMODULE );
	compiler_emit( cc, ex, "\tce\n", SLDC, &module_name );
	compiler_emit( cc, ex, "\tc\n", PEQBOOL );
	compiler_emit( cc, ex, "\tc\n", DUP );
	compiler_push_relative_fixup( cc, ex );
	compiler_emit( cc, ex, "\tce\n", BJNZ, &zero );
	compiler_emit( cc, ex, "\tc\n", DROP );
    }

    compiler_emit( cc, ex, "\n\tce\n", PLD, &try_var_offset );
    compiler_emit( cc, ex, "\n\tc\n", EXCEPTIONID );

    exception_val = exception ? dnode_ssize_value( exception ) : 0;
    compiler_emit( cc, ex, "\tce\n", LDC, &exception_val );
    compiler_emit( cc, ex, "\tc\n", EQBOOL );

    if( module ) {
	compiler_fixup_here( cc );
    }
}

static void compiler_finish_catch_comparisons( COMPILER *cc,
                                               int nfixups,
                                               cexception_t *ex )
{
    int i;
    ssize_t zero = 0;

    compiler_push_relative_fixup( cc, ex );
    compiler_emit( cc, ex, "\tce\n", BJZ, &zero );
    for( i = 0; i < nfixups; i ++ ) {
	/* fixup all JNZs emitted in the 'exception_identifier_list'
	   rule: */
	compiler_swap_fixups( cc );
	compiler_fixup_here( cc );
    }
}

static void compiler_finish_catch_block( COMPILER *cc, cexception_t *ex )
{
    ssize_t zero = 0;

    cc->catch_jumpover_nr ++;
    compiler_push_relative_fixup( cc, ex );
    compiler_emit( cc, ex, "\tce\n", JMP, &zero );
    compiler_swap_fixups( cc );
    compiler_fixup_here( cc );
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

static void compiler_convert_function_argument( COMPILER *cc,
                                                cexception_t *ex )
{
    TNODE *arg_type = cc->current_arg ? dnode_type( cc->current_arg ) : NULL;
    TNODE *exp_type = cc->e_stack ? enode_type( cc->e_stack ) : NULL;

    if( arg_type && exp_type ) {
	if( tnode_kind( arg_type ) != TK_PLACEHOLDER &&
	    !tnode_types_are_assignment_compatible( arg_type, exp_type,
                                                    NULL, NULL /* msg */,
                                                    0 /* msglen */, ex )) {
            char *arg_type_name = tnode_name( arg_type );
            if( arg_type_name ) {
                compiler_compile_type_conversion
                    ( cc, arg_type, /* target_name: */NULL,  ex );
            }
	}
    }
    cc->current_arg = cc->current_arg ? dnode_next( cc->current_arg ) : NULL;
}

static void compiler_compile_typed_const_value( COMPILER *cc,
                                                TNODE *const_type,
                                                const_value_t *v,
                                                cexception_t *ex )
{
    cexception_t inner;
    value_t vtype = v->value_type;
    TNODE * volatile tnode = NULL;

    cexception_guard( inner ) {
	switch( vtype ) {
	    case VT_INTMAX:
		const_value_to_string( v, &inner );
		compiler_compile_typed_constant( cc, const_type,
                                                 const_value_string( v ),
                                                 &inner );
		break;
	    case VT_FLOAT:
		const_value_to_string( v, &inner );
		compiler_compile_typed_constant( cc, const_type,
                                                 const_value_string( v ),
                                                 &inner );
		break;
	    case VT_STRING:
		const_value_to_string( v, &inner );
		compiler_compile_typed_constant( cc, const_type,
                                                 const_value_string( v ),
                                                 &inner );
		break;
	    case VT_ENUM:
		const_value_to_string( v, &inner );
		compiler_compile_typed_constant( cc, const_type,
                                                 const_value_string( v ),
                                                 &inner );
		break;
	    case VT_NULL: {
		    tnode = new_tnode_nullref( &inner );
		    compiler_push_typed_expression( cc, tnode, &inner );
		    tnode = NULL;
		    compiler_emit( cc, &inner, "\tc\n", PLDZ );
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

static void compiler_compile_multitype_const_value( COMPILER *cc,
                                                    const_value_t *v,
                                                    DNODE *module,
                                                    char *suffix_name,
                                                    cexception_t *ex )
{
    TNODE *const_type = NULL;
    value_t vtype = v->value_type;

    switch( vtype ) {
    case VT_INTMAX:
	const_type = compiler_lookup_suffix_tnode( cc, TS_INTEGER_SUFFIX,
                                                   module, suffix_name,
                                                   "integer" );
	break;
    case VT_FLOAT:
	const_type = compiler_lookup_suffix_tnode( cc, TS_FLOAT_SUFFIX,
                                                   module, suffix_name,
                                                   "float" );
	break;
    case VT_STRING:
	const_type = compiler_lookup_suffix_tnode( cc, TS_STRING_SUFFIX,
                                                   module, suffix_name,
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
	    compiler_compile_enumeration_constant( cc, module,
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

    compiler_compile_typed_const_value( cc, const_type, v, ex );
}

static void compiler_emit_default_arguments( COMPILER *cc,
                                             char *arg_name,
                                             cexception_t *ex )
{
    DNODE *arg;

    arg = cc->current_arg;
    while( arg && ( !arg_name || strcmp( arg_name, dnode_name( arg )) != 0 )) {
	if( dnode_has_initialiser( arg )) {
	    const_value_t const_value = make_zero_const_value();

	    const_value_copy( &const_value, dnode_value( arg ), ex );
	    compiler_compile_typed_const_value( cc, dnode_type( arg ),
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
	arg = dnode_next( arg );
    }
    if( arg == NULL && arg_name != NULL && cc->current_call ) {
	yyerrorf( "function '%s' has no argument '%s' to emit",
		  dnode_name( cc->current_call ), arg_name );
    }
    cc->current_arg = arg;
}

static void compiler_check_forward_functions( COMPILER *c )
{
    FIXUP *f;
    FIXUP *forward_calls = thrcode_forward_functions( c->thrcode );

    foreach_fixup( f, forward_calls ) {
	char *name = fixup_name( f );
	yyerrorf( "function %s() declared forward but never defined", name );
    }
}

static void compiler_check_raise_expression( COMPILER *c,
					     char *exception_name,
					     cexception_t *ex )
{
    TNODE *top_type = NULL;

    if( !c->e_stack ) {
	yyerrorf( "Not enough values on the stack for raising exception?" );
    } else if( !(top_type = enode_type( c->e_stack ))) {
	yyerrorf( "Value on the top of the stack is untyped when "
		  "raising exception?" );
    } else {
        compiler_check_and_compile_operator( c, top_type, "exceptionset", 1,
                                             NULL, ex );
    }
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
    { "ArrayIndexNegative",       SL_EXCEPTION_ARRAY_INDEX_NEGATIVE },
    { "ArrayIndexOverflow",       SL_EXCEPTION_ARRAY_INDEX_OVERFLOW },
    { "TruncatedInteger",         SL_EXCEPTION_TRUNCATED_INTEGER },
    { "UnimplementedMethod",      SL_EXCEPTION_UNIMPLEMENTED_METHOD },
    { "UnimplementedInterface",   SL_EXCEPTION_UNIMPLEMENTED_INTERFACE },

    { NULL, SL_EXCEPTION_NULL }
};

static void compiler_insert_default_exceptions( COMPILER *c,
                                                cexception_t *ex )
{
    int i;

    for( i = 0; default_exceptions[i].exception_name != NULL; i ++ ) {

	compiler_compile_exception( c, default_exceptions[i].exception_name,
				 default_exceptions[i].exception_nr, ex );

	c->latest_exception_nr = default_exceptions[i].exception_nr;

    }
}

static void compiler_compile_file_input_operator( COMPILER *cc,
                                                  cexception_t *ex )
{
    ENODE *top_expr = cc->e_stack;
    TNODE *top_type = top_expr ? enode_type( top_expr ) : NULL;

    if( top_type && tnode_is_addressof( top_type )) {
	top_type = tnode_element_type( top_type );
    }

    compiler_swap_thrcodes( cc );

    if( top_type ) {
	ENODE *file_expr = cc->e_stack;
	TNODE *file_type = file_expr ? enode_type( file_expr ) : NULL;

	if( file_type ) {
	    compiler_push_typed_expression( cc, share_tnode( file_type ), ex );
	} else {
	    compiler_push_typed_expression( cc, NULL, ex );
	}
	compiler_check_and_compile_operator( cc, top_type, ">>",
					  /*arity:*/ 1,
					  /*fixup_values:*/ NULL, ex );
	compiler_emit( cc, ex, "\n" );
    }

    compiler_merge_top_thrcodes( cc, ex );
    compiler_compile_swap( cc, ex );
    compiler_compile_sti( cc, ex );
}

static void compiler_check_non_null_variable( DNODE *dnode )
{
    TNODE *var_type = dnode_type( dnode );
    if( tnode_is_non_null_reference( var_type )) {
        yyerrorf( "'%s' was declared as non-null reference -- "
                  "it must be initialised", dnode_name( dnode ) );
    }
}

static void compiler_check_non_null_variables( DNODE *dnode_list )
{
    DNODE *var_dnode;

    foreach_dnode( var_dnode, dnode_list ) {
        compiler_check_non_null_variable( var_dnode );
    }
}

static void compiler_compile_variable_initialisations( COMPILER *cc,
                                                       DNODE *lst,
                                                       cexception_t *ex )
{
    DNODE *var;

    foreach_dnode( var, lst ) {
	if( dnode_has_flags( var, DF_HAS_INITIALISER )) {
	    compiler_compile_initialise_variable( cc, var, ex );
	} else {
            compiler_check_non_null_variable( var );
        }
    }
}

static void compiler_compile_zero_out_stackcells( COMPILER *cc,
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
	compiler_emit( cc, ex, "\tcee\n", ZEROSTACK, &min_offset, &nvars );
    }
}

static void compiler_begin_module( COMPILER *c,
                                   DNODE *volatile *module,
                                   cexception_t *ex )
{
    DNODE *volatile shared_module = NULL;
    assert( module );

    cexception_t inner;
    cexception_guard( inner ) {
        compiler_push_symbol_tables( c, &inner );
        shared_module = share_dnode( *module );
        vartab_insert_named_module( c->compiled_modules, &shared_module, 
                                    /* SYMTAB *st = */ NULL,
                                    &inner );
        
        shared_module = share_dnode( *module );
        vartab_insert_named( c->vartab, &shared_module, ex );
        dlist_push_dnode( &c->current_module_stack, &c->current_module, ex );
        // FIXME: share current_module in the future:
        delete_dnode( *module );
        c->current_module = *module;
        *module = NULL;
    }
    cexception_catch {
        delete_dnode( shared_module );
        cexception_reraise( inner, ex );
    }
}

static void compiler_end_module( COMPILER *c, cexception_t *ex )
{
    compiler_pop_symbol_tables( c );
    c->current_module = dlist_pop_data( &c->current_module_stack );
}

static char *compiler_find_module( COMPILER *c,
                                   const char *module_name,
                                   cexception_t *ex )
{
    static char buffer[300];
    ssize_t len;

    len = snprintf( buffer, sizeof(buffer), "%s.slib", module_name );

    assert( len < sizeof(buffer) );

    return buffer;
}

static int compiler_can_compile_use_statement( COMPILER *cc,
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

static void compiler_import_module( COMPILER *c,
                                    DNODE *module_name_dnode,
                                    cexception_t *ex )
{
    cexception_t inner;
    char *module_name = dnode_name( module_name_dnode );

    SYMTAB *volatile symtab = new_symtab( c->vartab, c->consts, c->typetab,
                                          c->operators, ex );


    DNODE *module = vartab_lookup_module( c->compiled_modules,
                                          module_name_dnode,
                                          symtab );

    DNODE *volatile shared_module = NULL;

#if 0
    printf( ">>> module = '%s', filename = '%s'\n",
            dnode_name( module_name_dnode ),
            dnode_filename( module_name_dnode ));
#endif

    cexception_guard( inner ) {
        if( compiler_can_compile_use_statement( c, "import" )) {
#if 0
            printf( ">>> can import module '%s'\n", module_name );
#endif
            if( module != NULL ) {
                char *synonim = dnode_synonim( module_name_dnode );
#if 0
                printf( ">>> will insert module '%s' as '%s'\n", module_name, synonim );
#endif
                shared_module = share_dnode( module );
                if( synonim ) {
                    vartab_insert_module( c->vartab, &shared_module,
                                          synonim, symtab, &inner );
                } else {
                    vartab_insert_named_module( c->vartab, &shared_module,
                                                symtab, &inner );
                }
#if 0
                printf( "found compiled module '%s'\n", module_name );
#endif
            } else {
                char *pkg_path = c->module_filename ?
                    c->module_filename : compiler_find_module( c, module_name,
                                                               &inner );
                compiler_open_include_file( c, pkg_path, &inner );
                assert( !c->requested_module  );
                c->requested_module = module_name_dnode;
            }
        }
    }
    cexception_catch {
        VARTAB *vt, *ct, *ot;
        TYPETAB *tt;
        delete_dnode( shared_module );
        obtain_tables_from_symtab( symtab, &vt, &ct, &tt, &ot );
        delete_symtab( symtab );
        cexception_reraise( inner, ex );
    }

    VARTAB *vt, *ct, *ot;
    TYPETAB *tt;
    obtain_tables_from_symtab( symtab, &vt, &ct, &tt, &ot );
    delete_symtab( symtab );
}

/* 
   FIXME: functions 'compiler_import_module()' and
   'compiler_use_module()' contain too much repetitive code and must
   be merged to maintain SPOT. S.G.
*/

static void compiler_use_module( COMPILER *c,
                                 DNODE *module_name_dnode,
                                 cexception_t *ex )
{
    cexception_t inner;

    char *module_name = dnode_name( module_name_dnode );

    SYMTAB *volatile symtab = new_symtab( c->vartab, c->consts, c->typetab,
                                          c->operators, ex );

    DNODE *module = vartab_lookup_module( c->compiled_modules,
                                          module_name_dnode,
                                          symtab );

    DNODE *volatile shared_module = NULL;
    
#if 0
    printf( "\n>>> module = '%s', filename = '%s'\n",
            dnode_name( module_name_dnode ),
            dnode_filename( module_name_dnode ));
#endif

    cexception_guard( inner ) {
        if( compiler_can_compile_use_statement( c, "use" )) {
#if 0
            printf( ">>> can use module '%s'\n", module_name );
#endif
            if( module != NULL ) {
                char *module_name = module ? dnode_name( module ) : NULL;
                DNODE *existing_module = module_name ?
                    vartab_lookup_module
                    ( c->vartab, module_name_dnode, symtab )
                    : NULL;
                char *synonim = dnode_synonim( module_name_dnode );
#if 0
                printf( "<<< existing_module == %p, synonim == %p >>>\n", 
                        existing_module, synonim );
#endif
                if( !existing_module || existing_module != module || synonim ) {
#if 0
                    printf( ">>> found module '%s' for reuse\n", 
                            module_name );
                    printf( ">>> will reinsert module '%s' as '%s'\n", 
                            module_name, 
                            synonim ? synonim : dnode_name( module ));
#endif
                    shared_module = share_dnode( module );
                    if( synonim ) {
#if 0
                        printf( ">>> reinserting synonim\n" );
#endif
                        vartab_insert_module( c->vartab, &shared_module ,
                                              synonim, symtab, &inner );
                    } else {
#if 0
                        printf( ">>> reinserting under its own name\n" );
#endif
                        vartab_insert_named_module( c->vartab, &shared_module,
                                                    symtab, &inner );
                    }
                }
#if 0
                printf( "found compiled module '%s'\n", module_name );
#endif
                compiler_use_exported_module_names( c, module, &inner );
            } else {
                char *pkg_path = c->module_filename ?
                    c->module_filename :
                    compiler_find_module( c, module_name, &inner );

#if 0
                printf( ">>> about to open file named '%s'\n", pkg_path );
#endif

                compiler_open_include_file( c, pkg_path, &inner );

                assert( !c->requested_module  );
                c->requested_module = module_name_dnode;

                if( c->use_module_name ) {
                    freex( c->use_module_name );
                    c->use_module_name = NULL;
                }
                c->use_module_name = strdupx( module_name, &inner );
            }
        }
    }
    cexception_catch {
        VARTAB *vt, *ct, *ot;
        TYPETAB *tt;
        delete_dnode( shared_module );
        obtain_tables_from_symtab( symtab, &vt, &ct, &tt, &ot );
        delete_symtab( symtab );
        cexception_reraise( inner, ex );
    }

    VARTAB *vt, *ct, *ot;
    TYPETAB *tt;
    obtain_tables_from_symtab( symtab, &vt, &ct, &tt, &ot );
    delete_symtab( symtab );
}

static void compiler_debug()
{
    printf( "Debug statement reached in line %d\n",
	    compiler_flex_current_line_number() );
}

static void compiler_compile_multiple_assignment( COMPILER *cc,
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
	compiler_compile_dropn( cc, nvalues - nvars, ex );
    }

    for( i = 0; i < nvars_left; i++ ) {
	compiler_merge_top_thrcodes( cc, ex );
	if( enode_is_varaddr( cc->e_stack )) {
	    DNODE *var = enode_variable( cc->e_stack );

	    share_dnode( var );
	    compiler_drop_top_expression( cc );
	    compiler_compile_variable_assignment( cc, var, ex );
	    delete_dnode( var );
	} else {
	    compiler_compile_swap( cc, ex );
	    compiler_compile_sti( cc, ex );
	}
    }
    compiler_swap_thrcodes( cc );
    compiler_merge_top_thrcodes( cc, ex );
}

static void compiler_compile_array_expression( COMPILER* cc,
                                               ssize_t nexpr,
                                               cexception_t *ex )
{
    ssize_t i;

    if( nexpr > 0 ) {
	ENODE *top = enode_list_pop( &cc->e_stack );
	TNODE *top_type = enode_type( top );
	ssize_t element_size = top_type ? tnode_size( top_type ) : 0;
	ssize_t nrefs = top_type && tnode_is_reference( top_type ) ? 1 : 0;

	for( i = 1; i < nexpr; i++ ) {
	    ENODE *curr = enode_list_pop( &cc->e_stack );
	    TNODE *curr_type = curr ? enode_type( curr ) : NULL;
            if( curr ) {
                if( !tnode_types_are_identical( top_type, curr_type, NULL, ex )) {
                    yyerrorf( "incompatible types of array components" );
                }
                delete_enode( curr );
            }
	}
	if( tnode_is_reference( top_type )) {
	    compiler_emit( cc, ex, "\tce\n", PMKARRAY, &nexpr );
	} else {
	    compiler_emit( cc, ex, "\tcsee\n", MKARRAY, &element_size,
                        &nrefs, &nexpr );
	}
	compiler_push_array_of_type( cc, share_tnode( top_type ), ex );
	delete_enode( top );
    }
}

static void compiler_push_loop( COMPILER *cc, char *loop_label,
                                int ncounters,
                                cexception_t *ex )
{
    char label[200];
    cc->loops =
	new_dnode_loop( loop_label, ncounters, cc->loops, ex );

    if( !loop_label ) {
	snprintf( label, sizeof(label), "@%p", cc->loops );
	dnode_set_name( cc->loops, label, ex );
    }
}

static void compiler_pop_loop( COMPILER *cc )
{
    DNODE *top_loop = cc->loops;

    assert( top_loop );
    cc->loops = dnode_next( top_loop );
    dnode_disconnect( top_loop );

    delete_dnode( top_loop );
}

static void compiler_fixup_op_continue( COMPILER *cc, cexception_t *ex )
{
    DNODE *loop = cc->loops;

    assert( loop );

    thrcode_fixup_op_continue( cc->thrcode, dnode_name( loop ),
			       thrcode_length( cc->thrcode ));
}

static void compiler_fixup_op_break( COMPILER *cc, cexception_t *ex )
{
    DNODE *loop = cc->loops;

    assert( loop );

    thrcode_fixup_op_break( cc->thrcode, dnode_name( loop ),
			    thrcode_length( cc->thrcode ));
}

static char *compiler_get_loop_name( COMPILER *cc, char *label )
{
    if( !label ) {
	DNODE *latest_loop = cc->loops;
	char *name = latest_loop ? dnode_name( latest_loop ) : NULL;
	return name;
    } else {
	return label;
    }
}

static ssize_t check_loop_types( COMPILER *cc, int omit_last_loop,
                                 char *label )
{
    DNODE *loop;
    int found = 0;
    ssize_t prev_count = 0;
    ssize_t count = 0;

    foreach_dnode( loop, cc->loops ) {
	if( dnode_has_flags( loop, DF_LOOP_HAS_VAL )) {
            prev_count = count;
	    count += dnode_loop_counters( loop );
	}
	if( strcmp( dnode_name(loop), label ) == 0 ) {
	    found = 1;
	    break;
	}
    }
    if( !found ) {
	yyerrorf( "label '%s' is not defined in the current scope", label );
    }
    return omit_last_loop ? prev_count : count;
}

static int compiler_check_break_and_cont_statements( COMPILER *cc )
{
    assert( cc );
    if( !cc->loops ) {
	yyerrorf( "'break' and 'continue' statements can be used "
		  "only in loops" );
	return 0;
    }
    return 1;
}

static void compiler_drop_loop_counters( COMPILER *cc, char *name,
                                         int delta,
                                         cexception_t *ex )
{
    ssize_t loop_counters = check_loop_types( cc, delta, name );

    if( loop_counters > 0 ) {
        compiler_emit( cc, ex, "\tce\n", PDROPN, &loop_counters );
    }
}

static void compiler_compile_break( COMPILER *cc, ssize_t label_idx,
                                    cexception_t *ex )
{
    ssize_t zero = 0;
    char *volatile label =
        obtain_string_from_strpool( cc->strpool, label_idx );
    cexception_t inner;

    cexception_guard( inner ) {
        if( compiler_check_break_and_cont_statements( cc )) {
            char *name = compiler_get_loop_name( cc, label );

            compiler_drop_loop_counters( cc, name, 0, &inner );

            if( name ) {
                thrcode_push_op_break_fixup( cc->thrcode, name, &inner );
            }
            compiler_emit( cc, &inner, "\tce\n", JMP, &zero );
        }
    }
    cexception_catch {
        freex( label );
        cexception_reraise( inner, ex );
    }
    freex( label );
}

static void compiler_compile_continue( COMPILER *cc, ssize_t label_idx,
                                       cexception_t *ex )
{
    ssize_t zero = 0;
    char *volatile label =
        obtain_string_from_strpool( cc->strpool, label_idx );
    cexception_t inner;

    cexception_guard( inner ) {
        if( compiler_check_break_and_cont_statements( cc )) {
            char *name = compiler_get_loop_name( cc, label );

            compiler_drop_loop_counters( cc, name, 1, &inner );

            if( name ) {
                thrcode_push_op_continue_fixup( cc->thrcode, name, &inner );
            }
	compiler_emit( cc, &inner, "\tce\n", JMP, &zero );
        }
    }
    cexception_catch {
        freex( label );
        cexception_reraise( inner, ex );
    }
    freex( label );
}

static void compiler_set_function_arguments_readonly( TNODE *funct_type )
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

static void compiler_check_default_value_compatibility( DNODE *arg,
						     const_value_t *val )
{
    TNODE *arg_type = dnode_type( arg );
    type_kind_t arg_kind = arg_type ? tnode_kind( arg_type ) : TK_NONE;
    value_t val_kind = const_value_type( val );

    if( arg_kind == TK_INTEGER || arg_kind == TK_BOOL ) {
	if( val_kind != VT_INTMAX ) {
	    yyerrorf( "default value is not compatible with the "
		      "function argument '%s' of type '%s'",
		      dnode_name( arg ), tnode_name( arg_type ));
	}
    } else
    if( arg_kind == TK_REAL ) {
	if( val_kind != VT_FLOAT && val_kind != VT_INTMAX ) {
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
	return make_const_value( ex, VT_INTMAX,
                                 (intmax_t)sizeof(stackcell_t) );
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
	return make_const_value
            ( ex, VT_INTMAX, (intmax_t)tnode_size( tnode ));
    } else
    if( strcmp( attribute_name, "nref" ) == 0 ) {
	return make_const_value
            ( ex, VT_INTMAX, (intmax_t)tnode_number_of_references( tnode ));
    }
    if( strcmp( attribute_name, "kind" ) == 0 ) {
	return make_const_value
            ( ex, VT_INTMAX, (intmax_t)tnode_kind( tnode ));
    }
    if( strcmp( attribute_name, "isref" ) == 0 ) {
	return make_const_value
            ( ex, VT_INTMAX, (intmax_t)(tnode_is_reference( tnode ) ? 1 : 0));
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
	return
            make_const_value( ex, VT_INTMAX, (intmax_t)dnode_offset( dnode ));
    } else {
	TNODE *tnode = dnode_type( dnode );
	return compiler_get_tnode_compile_time_attribute( tnode,
							  attribute_name, ex );
    }
}

static const_value_t compiler_make_compile_time_value( COMPILER *cc,
						       DNODE *module,
						       char *identifier,
						       char *attribute_name,
						       cexception_t *ex )
{
    DNODE *variable = NULL;
    TNODE *tnode = NULL;

    variable = compiler_lookup_dnode_silently( cc, module, identifier );

    if( !variable ) {
	tnode = compiler_lookup_tnode_silently( cc, module, identifier );
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

static DNODE* compiler_lookup_type_field( COMPILER *cc,
					  DNODE *module,
					  char *identifier,
					  char *field_identifier )
{
    DNODE *variable = NULL;
    TNODE *tnode = NULL;
    DNODE *field;

    variable = compiler_lookup_dnode_silently( cc, module, identifier );

    if( !variable ) {
	tnode = compiler_lookup_tnode_silently( cc, module, identifier );
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

static DNODE* compiler_lookup_tnode_field( COMPILER *cc,
                                           TNODE *tnode,
                                           char *field_identifier )
{
    DNODE *field;

    if( tnode ) {
	field = tnode_lookup_field( tnode, field_identifier );
	if( !field ) {
	    yyerrorf( "type '%s' does not have member '%s'",
		      tnode_name( tnode ), field_identifier );
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

static void compiler_load_library( COMPILER *compiler,
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
        compiler_find_include_file( compiler, library_filename, ex );

    if( !library_path  ) {
        freex( library_name );
        yyerrorf( "could not find shared library '%s' in the include path",
                  library_filename );
        cexception_raise
            ( ex, COMPILER_FILE_SEARCH_ERROR,
              "could not find required shared libraries, terminating." );
        return;
    }

    strncpy( library_name, library_name_start, library_name_length );

    cexception_guard( inner ) {
	const char *opcodes_symbol = "OPCODES";
	DL_HANDLE *lib = dlopen( library_path, RTLD_LAZY );

	if( !lib ) {
	    char *errmsg = dlerror();
            /*
	    errmsg = rindex( errmsg, ':' );
	    if( errmsg ) errmsg ++;
	    if( errmsg && *errmsg == ' ' ) errmsg ++;
            */
	    if( errmsg && *errmsg ) {
		yyerrorf( "%c%s",
			  tolower(*errmsg), errmsg+1 );
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

static void compiler_push_current_interface_nr( COMPILER *cc,
                                                cexception_t *ex )
{
    push_ssize_t( &cc->current_interface_nr_stack,
                  &cc->current_interface_nr_stack_size,
                  cc->current_interface_nr, ex );
}

static void compiler_push_current_call( COMPILER *cc,
                                        cexception_t *ex )
{
    dlist_push_dnode( &cc->current_call_stack,
                      &cc->current_call, ex );

    dlist_push_dnode( &cc->current_arg_stack,
                      &cc->current_arg, ex );
}

static void compiler_pop_current_interface_nr( COMPILER *cc,
                                               cexception_t *ex )
{
    cc->current_interface_nr =
        pop_ssize_t( &cc->current_interface_nr_stack,
                     &cc->current_interface_nr_stack_size,
                     ex );
}

static void compiler_pop_current_call( COMPILER *cc,
                                       cexception_t *ex )
{
    cc->current_call =
	dlist_pop_data( &cc->current_call_stack );
    cc->current_arg =
	dlist_pop_data( &cc->current_arg_stack );
}

static void compiler_check_and_push_function_name( COMPILER *cc,
                                                   DNODE *module,
                                                   char *function_name,
                                                   cexception_t *ex )
{
    TNODE *fn_tnode = NULL;
    type_kind_t fn_kind;

    compiler_push_current_interface_nr( cc, ex );
    compiler_push_current_call( cc, ex );

    cc->current_call = 
	share_dnode( compiler_lookup_dnode( cc, module, function_name,
                                            "function" ));

    fn_tnode = cc->current_call ?
	dnode_type( cc->current_call ) : NULL;

    fn_kind = fn_tnode ? tnode_kind( fn_tnode ) : TK_NONE;

    if( fn_tnode &&
        fn_kind != TK_FUNCTION_REF &&
	fn_kind != TK_FUNCTION &&
	fn_kind != TK_OPERATOR &&
        fn_kind != TK_CLOSURE ) {
	char *fn_name = cc->current_call ?
	    dnode_name( cc->current_call ) : NULL;
	if( fn_name ) {
	    yyerrorf( "call to non-function '%s'", fn_name );
	} else {
	    yyerrorf( "call to non-function" );
	}
    }
}

static ssize_t compiler_compile_multivalue_function_call( COMPILER *cc,
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
            compiler_emit_default_arguments( cc, NULL, &inner );
            compiler_check_and_drop_function_args( cc, funct, generic_types,
                                                   &inner );
            compiler_emit_function_call( cc, funct, NULL, "\n", &inner );
            if( tnode_kind( fn_type ) == TK_FUNCTION_REF ||
                tnode_kind( fn_type ) == TK_CLOSURE ) {
                compiler_drop_top_expression( cc );
            }
            compiler_push_function_retvals( cc, funct, generic_types, &inner );
            rval_nr = compiler_count_return_values( funct );
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
            compiler_push_error_type( cc, &inner );
            rval_nr = 1;
        }
	delete_typetab( generic_types );
    }
    cexception_catch {
	delete_typetab( generic_types );
        cexception_reraise( inner, ex );
    }

    delete_dnode( cc->current_call );

    compiler_pop_current_interface_nr( cc, ex );
    compiler_pop_current_call( cc, ex );

    return rval_nr;
}

/*

             <--- ssize_t --->
             alloccell_t:
             +...............+
             |               |
             | ...           |
             +---------------+
             | vmt_address   |>-\
             +---------------+  |
                                |
VMT layout:                     |
                                |
itable[]:                       |
---------                       |
                                |
             +---------------+  |
          -2 |base2 VMT offs.|  | VMT of the super-super-class
             +---------------+  |
          -1 |base  VMT offs.|  | VMT of the super-class
             +---------------+  |
vmt_address: | n_interfaces  |<-/
             +---------------+
             |class VMT offs.|->--\
             +---------------+    |
             |i-face 1 VMT o.|>-\ |
             +---------------+  | |
             |i-face 2 VMT o.|  | |
             +---------------+  | |
             |               |  | |
             | ...           |  | |
             +---------------+  | |
             |i-face n VMT o.|  | |
             +---------------+  | |
                                | |
vtable[]:                       | |
---------                       | |
static data +                   | |
i-face 1 VMT offs.:             | |
             +---------------+  | |
           0 | nr of methods |<-/ |
             +---------------+    |
           1 | method 1 offs.|    |
             +---------------+    |
             |               |    |
             | ...           |    |
             +---------------+    |
           k | method k offs.|    | k = nr of methods
             +---------------+    |
                                  |
                                  |
             +---------------+    |
           0 | nr of methods |<---/
             +---------------+
           1 | destructor of.|
             +---------------+
           2 | method 1 offs.|
             +---------------+
           3 | method 2 offs.|
             +---------------+
             |               |
             | ...           |
             +---------------+
           l | method l offs.| l = nr of methods 
             +---------------+

*/

static void compiler_start_virtual_method_table( COMPILER *cc,
                                                 TNODE *class_descr,
                                                 cexception_t *ex )
{
    ssize_t vmt_address;
    ssize_t interface_nr, base_class_nr;

    assert( class_descr );

    if( tnode_kind( class_descr ) == TK_INTERFACE ) {
        return;
    }

    base_class_nr = tnode_base_class_count( class_descr );

    interface_nr = tnode_max_interface( class_descr );

    compiler_assemble_static_alloc_hdr( cc, sizeof(ssize_t),
                                        sizeof(ssize_t), ex );

    if( base_class_nr > 0 )
        compiler_assemble_static_data( cc, NULL, base_class_nr * sizeof(ssize_t), ex );

    vmt_address = compiler_assemble_static_ssize_t( cc, 1 + interface_nr, ex );

    tnode_set_vmt_offset( class_descr, vmt_address );

    compiler_assemble_static_data( cc, NULL,
				   (1+interface_nr) * sizeof(ssize_t), ex );

    /* Populate base class VMT references at negative offsets. The
       following code assumes that the virtual method tables of the
       base classes have been finished already: */

    if( base_class_nr > 0 ) {
        ssize_t base_class_nr = -1;
        TNODE *base_class = tnode_base_type( class_descr );
        ssize_t *vmt = (ssize_t*)(cc->static_data + vmt_address);
        while( base_class && tnode_kind( base_class ) == TK_CLASS ) {
            ssize_t base_vmt_offset = tnode_vmt_offset( base_class );
            ssize_t *itable = (ssize_t*)(cc->static_data + base_vmt_offset);
            vmt[base_class_nr] = itable[1];
            base_class = tnode_base_type( base_class );
            base_class_nr --;
        }
    }
}
 
static void compiler_lookup_interface_method( COMPILER *cc, 
                                              TNODE *class_descr,
                                              ssize_t interface_number,
                                              ssize_t method_number,
                                              TNODE **ret_interface,
                                              DNODE **ret_method )
{
    TLIST *interface_list = tnode_interface_list( class_descr );
    TLIST *interface_node;

    assert( ret_interface );
    assert( ret_method );

    foreach_tlist( interface_node, interface_list ) {
        TNODE *current_interface = tlist_data( interface_node );
        TNODE *base_interface;
        for( base_interface = current_interface; base_interface;
             base_interface = tnode_base_type( base_interface )) {
            ssize_t method_interface =
                tnode_interface_number( base_interface );
            if( method_interface + 1 != interface_number )
                continue;
            DNODE *methods = tnode_methods( base_interface );
            DNODE *method;
            foreach_dnode( method, methods ) {
                ssize_t method_index = dnode_offset( method );
                if( method_index == method_number ) {
                    *ret_interface = base_interface;
                    *ret_method = method;
                    return;
                }
            }
        }
    }
}

static void compiler_finish_virtual_method_table( COMPILER *cc,
                                                  TNODE *class_descr,
                                                  cexception_t *ex )
{
    ssize_t vmt_address, vmt_start, i;
    ssize_t max_vmt_entry;
    ssize_t interface_nr;
    ssize_t *itable; /* interface VMT offset table */
    ssize_t *vtable; /* a VMT table with method offsets*/
    DNODE *volatile method;
    TNODE *volatile base;

    assert( class_descr );
    assert( tnode_kind( class_descr ) != TK_INTERFACE );

    vmt_address = tnode_vmt_offset( class_descr );
    max_vmt_entry = tnode_max_vmt_offset( class_descr );
    interface_nr = tnode_max_interface( class_descr );

    if( tnode_destructor( class_descr ) && max_vmt_entry == 0 ) {
        max_vmt_entry++;
    }

    vmt_start =
	compiler_assemble_static_ssize_t( cc, max_vmt_entry, ex );

    itable = (ssize_t*)(cc->static_data + vmt_address);
    itable[1] = vmt_start;

    /* allocate the main class VMT: */
    compiler_assemble_static_data( cc, NULL,
				   max_vmt_entry * sizeof(ssize_t), ex );

    /* Temporarily, let's store method counts instead of interface vmt
       offsets in the first layer of the VMT (the itable). Later, we
       will allocate VMT's for each interface, for exactely the stored
       number of methods (plus one entry for the method count), and
       replace the method counts here with the VMT offsets. */
    /* The 'itable' pointer MUST be reinitialised after each call to
       'compiler_assemble_static_data', since the static data compiler
       MAY reallocate the static data area cc->static_data: */
    itable = (ssize_t*)(cc->static_data + vmt_address);
    TLIST *interface_list = tnode_interface_list( class_descr );
    TLIST *interface_node;
    foreach_tlist( interface_node, interface_list ) {
        TNODE *current_interface = tlist_data( interface_node );
        TNODE *base_interface;
        for( base_interface = current_interface; base_interface;
             base_interface = tnode_base_type( base_interface )) {
            ssize_t interface_nr = tnode_interface_number( base_interface );
            ssize_t method_count =
                dnode_list_length( tnode_methods( base_interface ));
            if( interface_nr > 0 &&
                itable[interface_nr+1] < method_count ) {
                itable[interface_nr+1] = method_count;
            }
        }
    }

    /* Now, let's allocate VMTs for methods and replace itable[]
       entries with table offsets: */
    for( i = 2; i <= interface_nr+1; i++ ) {
        ssize_t method_count = itable[i];
        ssize_t itable_offset;
        itable_offset = compiler_assemble_static_data( cc, NULL,
                                                       (method_count + 1) *
                                                       sizeof(ssize_t), ex );
        /* The 'itable' pointer MUST be reinitialised after each call
           to 'compiler_assemble_static_data', since the static data
           compiler MAY reallocate the static data area
           cc->static_data: */
        itable = (ssize_t*)(cc->static_data + vmt_address);
        itable[i] = itable_offset;
        ((ssize_t*)(cc->static_data + itable[i]))[0] = method_count;
    }

    /* Add destructor address if present: */
    itable = (ssize_t*)(cc->static_data + vmt_address);

    DNODE *destructor = tnode_destructor( class_descr );
    if( destructor ) {
        vtable = (ssize_t*)(cc->static_data + itable[1]);
        ssize_t destructor_address = dnode_offset( destructor );
        vtable[1] = destructor_address;
    }

    /* Now, fill the VMT table with the real method addresses: */
    foreach_tnode_base_class( base, class_descr ) {
	DNODE *methods = tnode_methods( base );
	foreach_dnode( method, methods ) {
	    ssize_t method_index = dnode_offset( method );
	    ssize_t method_address = dnode_ssize_value( method );
            TNODE *method_type = dnode_type( method );
            ssize_t method_interface = method_type ?
                tnode_interface_number( method_type ) : -1;
            vtable = (ssize_t*)(cc->static_data + itable[method_interface+1]);
            if( vtable[method_index] == 0 ) {
                vtable[method_index] = method_address;
            }
	}
    }
    /* Fill in adresses of default method implementations provided by
       some interfaces: */
    {
        TLIST *interface_list = tnode_interface_list( class_descr );
        TLIST *interface_node;
        foreach_tlist( interface_node, interface_list ) {
            TNODE *current_interface = tlist_data( interface_node );
            TNODE *base_interface;
            for( base_interface = current_interface; base_interface;
                 base_interface = tnode_base_type( base_interface )) {
                ssize_t method_interface =
                    tnode_interface_number( base_interface );
                DNODE *methods = tnode_methods( base_interface );
                DNODE *method;
                vtable = (ssize_t*)
                    (cc->static_data + itable[method_interface+1]);
                foreach_dnode( method, methods ) {
                    ssize_t method_index = dnode_offset( method );
                    ssize_t method_address = dnode_ssize_value( method );
                    if( vtable[method_index] == 0 && method_address != 0 ) {
                        vtable[method_index] = method_address;
                    }
                }
            }
        }
    }

    /* check whether all methods are implemented: */

    {
        DNODE *methods = tnode_methods( class_descr );
        char *class_name = class_descr ? tnode_name( class_descr ) : "???";
	foreach_dnode( method, methods ) {
	    /* ssize_t method_index = dnode_offset( method ); */
	    ssize_t method_address = dnode_ssize_value( method );
            TNODE *method_type = dnode_type( method );
            ssize_t method_interface = method_type ?
                tnode_interface_number( method_type ) : -1;
            if( method_address == 0 ) {
                yyerrorf( "class '%s', interface %d, method '%s' is declared "
                          "but not implemented\n",
                          class_name, method_interface, 
                          method ? dnode_name( method ) : "???" );
            }
        }

        /* Check whether all methods of all interfaces are defined: */
        for( i = 2; i <= interface_nr + 1; i++ ) {
            ssize_t j, method_count;
            vtable = (ssize_t*)(cc->static_data + itable[i]);
            method_count = vtable[0];
            for( j = 1; j <= method_count; j++ ) {
                if( vtable[j] == 0 ) {
                    TNODE *interface_tnode = NULL;
                    DNODE *interface_method = NULL;
                    compiler_lookup_interface_method
                        ( cc, class_descr, i, j,
                          &interface_tnode, &interface_method );
                    if( interface_method ) {
                        yyerrorf( "class '%s' does not implement method "
                                  "'%s' from interface '%s'",
                                  tnode_name(class_descr),
                                  dnode_name( interface_method ),
                                  tnode_name( interface_tnode ));
                    } else {
                        yyerrorf( "class '%s' does not implement iterface method "
                                  "(interface %d, method %d)",
                                  tnode_name(class_descr), i, j );
                    }
                }
            }
        }
    }
}

static void compiler_check_array_component_is_not_null( TNODE *tnode,
                                                        ENODE *array_length_expr )
{
    if( tnode_is_non_null_reference( tnode ) &&
        ( array_length_expr == NULL || 
          !enode_has_flags( array_length_expr, EF_IS_ZERO ) )) {
        char *type_name = tnode_name( tnode );
        if( type_name ) {
            yyerrorf( "type '%s' is a non-null reference -- "
                      "please use array expressions to initialise array elements",
                      type_name );
        } else {
            yyerrorf( "array element is a non-null reference -- "
                      "please use array expressions to initialise array elements" );
        }
    }
}

static void compiler_check_type_contains_non_null_ref( TNODE *tnode )
{
    if( tnode_has_non_null_ref_field( tnode ) &&
        tnode_kind( tnode ) != TK_CLASS ) {
        char *type_name = tnode_name( tnode );
        if( type_name ) {
            yyerrorf( "type '%s' contains non-null fields -- "
                      "please use struct expressions to initialise them",
                      type_name );
        } else {
            yyerrorf( "structure contains non-null fields -- "
                      "please use structure expressions to initialise them" );
        }
    }
}

static void push_string( char ***array, char *string, cexception_t *ex )
{
    ssize_t len = string_count( *array );

    *array = reallocx( *array, sizeof((*array)[0]) * (len + 2), ex );
    (*array)[len+1] = NULL;
    (*array)[len] = string;
}

static void unshift_string( char ***array, char *string, cexception_t *ex )
{
    ssize_t len = string_count( *array );
    ssize_t i;

    *array = reallocx( *array, sizeof((*array)[0]) * (len + 2), ex );
    for( i = len; i > 0; i-- ) {
        (*array)[i] = (*array)[i-1];
    }
    (*array)[len+1] = NULL;
    (*array)[0] = string;
}

static void compiler_set_string_pragma( COMPILER *c, char *pragma_name,
                                        char *value, cexception_t *ex )
{
    cexception_t inner;
    if( strcmp( pragma_name, "path" ) == 0 ) {
        delete_string_array( &c->include_paths );
        char *volatile spath = simplify_path( c->filename, ex );
        char *volatile interpolated = NULL;
        cexception_guard( inner ) {
            interpolated = interpolate_string( value, spath, &inner );
#if 0
            printf( ">>> path = '%s'\n>>> spath = '%s'\n"
                    ">>> interpolated = '%s'\n", value, spath, interpolated );
#endif
            push_string( &c->include_paths, interpolated, &inner );
        }
        cexception_catch {
            freex( interpolated );
            freex( spath );
            cexception_reraise( inner, ex );
        }
        freex( spath );
    } else if( strcmp( pragma_name, "append" ) == 0 ) {
        char *volatile spath = simplify_path( c->filename, ex );
        char *volatile interpolated = NULL;
        cexception_guard( inner ) {
            interpolated = interpolate_string( value, spath, &inner );
#if 0
            printf( ">>> appending path = '%s'\n>>> spath = '%s'\n"
                    ">>> interpolated = '%s'\n", value, spath, interpolated );
#endif
            push_string( &c->include_paths, interpolated, &inner );
        }
        cexception_catch {
            freex( interpolated );
            cexception_reraise( inner, ex );
        }
        freex( spath );
    } else if( strcmp( pragma_name, "prepend" ) == 0 ) {
        char *volatile spath = simplify_path( c->filename, ex );
        char *volatile interpolated = NULL;
        cexception_guard( inner ) {
            interpolated = interpolate_string( value, spath, &inner );
#if 0
            printf( ">>> prepending path = '%s'\n>>> spath = '%s'\n"
                    ">>> interpolated = '%s'\n", value, spath, interpolated );
#endif
            unshift_string( &c->include_paths, interpolated, &inner );
        }
        cexception_catch {
            freex( interpolated );
            cexception_reraise( inner, ex );
        }
        freex( spath );
    } else {
        yyerrorf( "unknown pragma '%s' with string value", pragma_name );
    }
}

static void compiler_set_integer_pragma( COMPILER *c, char *pragma_name,
                                         ssize_t value )
{
    ssize_t old_value;

    if( strcmp( pragma_name, "stacksize" ) == 0 ) {
        old_value = interpret_rstack_length( value );
        if( old_value > value ) {
            interpret_rstack_length( old_value );
        }
        old_value = interpret_estack_length( value );
        if( old_value > value ) {
            interpret_estack_length( old_value );
        }
    } else if( strcmp( pragma_name, "stackdelta" ) == 0 ) {
        old_value = interpret_stack_delta( value );
        if( old_value > value ) {
            interpret_stack_delta( old_value );
        }
    } else {
        yyerrorf( "unknown pragma '%s' with integer value", pragma_name );
    }
}

static void compiler_import_selected_names( COMPILER *c,
                                            DNODE *volatile *imported_identifiers,
                                            char *module_name,
                                            int keyword,
                                            cexception_t *ex )
{
    assert( imported_identifiers );
    DNODE *module = 
        vartab_lookup( c->compiled_modules, module_name );
    DNODE *identifier;
    if( !module ) {
        yyerrorf( "module '%s' is not found -- consider 'use %s' first",
                  module_name, module_name );
    } else {
        foreach_dnode( identifier, *imported_identifiers ) {
            char *name = dnode_name( identifier );
            DNODE *identifier_dnode =
                dnode_vartab_lookup_var( module, name );
            DNODE *shared_dnode = NULL;
            cexception_t inner;

            cexception_guard( inner ) {
                if( identifier_dnode ) {
                    TNODE *identifier_type = dnode_type( identifier_dnode );
                    type_kind_t identifier_kind = tnode_kind( identifier_type );
                    if( keyword != 0 ) {
                        if( keyword == IMPORT_FUNCTION && 
                            identifier_kind != TK_FUNCTION ) {
                            yyerrorf( "imported name '%s' should be a function "
                                      "or a procedure, but it is a variable",
                                      name );
                        }
                        if( keyword == IMPORT_VAR && 
                            identifier_kind == TK_FUNCTION ) {
                            yyerrorf( "imported name '%s' should be a variable "
                                      "or a procedure, but it is a %s",
                                      name, tnode_kind_name( identifier_type ));
                        }
                    }
                    shared_dnode = share_dnode( identifier_dnode );
                    vartab_insert( c->vartab, name, &shared_dnode, &inner );
                } else {
                    yyerrorf( "name '%s' is not found in module '%s'",
                              name, module_name );
                }
            }
            cexception_catch {
                delete_dnode( shared_dnode );
                dispose_dnode( imported_identifiers );
                cexception_reraise( inner, ex );
            }
        }
    }
    dispose_dnode( imported_identifiers );
}

static DNODE* compiler_module_parameter_dnode( COMPILER *c,
                                               ssize_t parameter_name_idx,
                                               ssize_t parameter_default_idx,
                                               type_kind_t kind,
                                               cexception_t *ex )
{
    char *parameter_name =
        obtain_string_from_strpool( c->strpool, parameter_name_idx );
    char *parameter_default =
        obtain_string_from_strpool( c->strpool, parameter_default_idx );
    cexception_t inner;
    TNODE *volatile dnode_type = tnode_set_kind( new_tnode( ex ), kind );
    DNODE *volatile parameter_dnode = NULL;

    cexception_guard( inner ) {
        parameter_dnode = new_dnode_name( parameter_name, &inner );
        dnode_insert_type( parameter_dnode, dnode_type );
        /* We will use the 'synonim' field to pass the default module
           parameter name: */
        dnode_set_synonim( parameter_dnode, parameter_default, &inner );
        freex( parameter_default );
    }
    cexception_catch {
        delete_tnode( dnode_type );
        cexception_reraise( inner, ex );
    }

    return parameter_dnode;
}

static void compiler_import_array_definition( COMPILER *c, char *module_name,
                                              cexception_t *ex )
{
    DNODE *module = 
        vartab_lookup( c->compiled_modules, module_name );

    if( !module ) {
        yyerrorf( "module '%s' is not found for type import "
                  "-- consider 'use %s' first",
                  module_name, module_name );
    } else {
        char *name = "array";
        TNODE *volatile identifier_tnode =
            share_tnode( dnode_typetab_lookup_type( module, name ));

        cexception_t inner;
        cexception_guard( inner ) {
            if( identifier_tnode ) {
                if( typetab_lookup( c->typetab, name )) {
                    yyerrorf( "type named '%s' is already defined -- "
                              "can not import", name );
                } else {
                    typetab_insert( c->typetab, name, &identifier_tnode,
                                    &inner );
                }
            } else {
                yyerrorf( "type '%s' is not found in module '%s'",
                          name, module_name );
            }
        }
        cexception_catch {
            delete_tnode( identifier_tnode );
            cexception_reraise( inner, ex );
        }
    }
}

static void compiler_import_type_identifier_list( COMPILER *c, 
                                                  DNODE *volatile *imported_identifiers,
                                                  char *module_name,
                                                  cexception_t *ex )
{
    DNODE *module = 
        vartab_lookup( c->compiled_modules, module_name );

    if( !module ) {
        yyerrorf( "module '%s' is not found for type import "
                  "-- consider 'use %s' first",
                  module_name, module_name );
    } else {
        DNODE *identifier;
        foreach_dnode( identifier, *imported_identifiers ) {
            char *name = dnode_name( identifier );
            TNODE *identifier_tnode =
                share_tnode( dnode_typetab_lookup_type( module, name ));
            TNODE *shared_tnode =
                share_tnode( identifier_tnode );

            cexception_t inner;
            cexception_guard( inner ) {
                if( identifier_tnode ) {
                    if( typetab_lookup( c->typetab, name )) {
                        yyerrorf( "type named '%s' is already defined -- "
                                  "can not import", name );
                    } else {
                        typetab_insert( c->typetab, name, &shared_tnode,
                                        &inner );
                        type_kind_t kind = tnode_kind( identifier_tnode );
                        char *suffix = tnode_suffix( identifier_tnode );
                        if( !suffix ) suffix = "";
                        if( kind == TK_INTEGER || kind == TK_REAL || 
                            kind == TK_STRING || suffix != NULL ) {
                            type_suffix_t suffix_kind = TS_NOT_A_SUFFIX;
                            switch( kind ) {
                            case TK_INTEGER: suffix_kind = TS_INTEGER_SUFFIX; break;
                            case TK_REAL:    suffix_kind = TS_FLOAT_SUFFIX; break;
                            case TK_STRING:  suffix_kind = TS_STRING_SUFFIX; break;
                            default:
                                break;
                            }
                            if( suffix_kind != TS_NOT_A_SUFFIX ) {
                                typetab_override_suffix
                                    ( c->typetab, suffix, suffix_kind,
                                      &identifier_tnode, ex );
                            }
                        }
                    }
                } else {
                    yyerrorf( "type '%s' is not found in module '%s'",
                              name, module_name );
                }
            }
            cexception_catch {
                delete_tnode( shared_tnode );
                delete_tnode( identifier_tnode );
                dispose_dnode( imported_identifiers );
                cexception_reraise( inner, ex );
            }
            dispose_tnode( &shared_tnode );
            dispose_tnode( &identifier_tnode );
        }
    }
    dispose_dnode( imported_identifiers );
}

static void compiler_import_selected_constants( COMPILER *c,
                                                DNODE *volatile *imported_identifiers, 
                                                char *module_name,
                                                cexception_t *ex )
{
    DNODE *module = 
        vartab_lookup( c->compiled_modules, module_name );

    assert( imported_identifiers );

    if( !module ) {
        yyerrorf( "module '%s' is not found for constant import "
                  "-- consider 'use %s' first",
                  module_name, module_name );
    } else {
        DNODE *identifier;
        DNODE *volatile shared_identifier = NULL;
        cexception_t inner;
        cexception_guard( inner ) {
            foreach_dnode( identifier, *imported_identifiers ) {
                char *name = dnode_name( identifier );
                DNODE *identifier_dnode =
                    dnode_consttab_lookup_const( module, name );
                if( identifier_dnode ) {
                    shared_identifier = share_dnode( identifier_dnode );
                    vartab_insert( c->consts, name, &shared_identifier,
                                   &inner );
                } else {
                    yyerrorf( "constant '%s' is not found in module '%s'",
                              name, module_name );
                }
            }
        }
        cexception_catch {
            delete_dnode( shared_identifier );
            cexception_reraise( inner, ex );
        }
    }
    dispose_dnode( imported_identifiers );
}

static void compiler_process_module_parameters( COMPILER *cc,
                                                DNODE *module_params,
                                                cexception_t *ex )
{
#if 0
    printf( ">>> There is a requested module '%s'\n",
            dnode_name( cc->requested_module ));
#endif
    DNODE *arg, *param, *module_args =
        dnode_module_args( cc->requested_module );

    TYPETAB *ttab =
        symtab_typetab( stlist_data( cc->symtab_stack ));
    arg = module_args;
    foreach_dnode( param, module_params ) {
        TNODE *param_type = dnode_type( param );
        char *argument_name;
        if( !arg ) {
            /* maybe paremeter has a default value? Check: */
            argument_name = dnode_synonim( param );
            if( !argument_name ) {
                /* No default value -- an error: */
                COMPILER_STATE *st = cc->include_files;
                char *filename = st ? st->filename : NULL;
                int line_no = st ? st->line_no : 0;
                if( filename ) {
                    yyerrorf( "missing actual argument for "
                              "parameter '%s' of module '%s' "
                              "included from file '%s', line %d",
                              dnode_name( param ),
                              dnode_name( cc->requested_module ),
                              filename, line_no );
                } else {
                    yyerrorf( "missing actual argument for "
                              "parameter '%s' of module '%s'",
                              dnode_name( param ),
                              dnode_name( cc->requested_module ));
                }
                break;
            }
        } else {
            argument_name = dnode_name( arg );
        }
        if( tnode_kind( param_type ) == TK_TYPE ) {
            TNODE *arg_type = argument_name ?
                typetab_lookup( ttab, argument_name ) :
                NULL;
            if( !arg_type ) {
                if( argument_name ) {
                    yyerrorf( "type '%s' is not defined for "
                              "module parameter",
                              argument_name );
                } else {
                    yyerrorf( "type is not defined for "
                              "module parameter '%s'",
                              dnode_name( param ));
                }
            }
            char *type_name = dnode_name( param );
            cexception_t inner;
            TNODE * volatile shared_arg_type = NULL;
            TNODE * volatile type_tnode =
                new_tnode_equivalent( arg_type, ex );
            cexception_guard( inner ) {
                tnode_set_name( type_tnode, type_name, &inner );
                compiler_typetab_insert( cc, &type_tnode, &inner );
                shared_arg_type = share_tnode( arg_type );
                tnode_insert_base_type( param_type, &shared_arg_type );
            }
            cexception_catch {
                delete_tnode( type_tnode );
                delete_tnode( shared_arg_type );
                cexception_reraise( inner, ex );
            }
        } else if( tnode_kind( param_type ) == TK_CONST ) {
            VARTAB *ctab =
                symtab_consttab( stlist_data( cc->symtab_stack ));
            DNODE *argument_dnode =
                vartab_lookup( ctab, argument_name );
            if( !argument_dnode && dnode_name( arg ) == NULL ) {
                /* The 'arg' dnode represents a constant expression: */
                DNODE *volatile shared_arg = NULL;
                cexception_t inner;
                const_value_t volatile const_value = make_zero_const_value();

                const_value_copy( (const_value_t*)&const_value,
                                  dnode_value( arg ), ex );
                
                cexception_guard( inner ) {
                    const_value_to_string( (const_value_t*)&const_value,
                                           &inner );
                    dnode_set_name( arg,
                                    strdupx( const_value_string
                                             ( (const_value_t*)&const_value ),
                                             &inner ),
                                    &inner );
                    argument_dnode = arg;
                    shared_arg = share_dnode( arg );
                    vartab_insert_named( ctab, &shared_arg, &inner );
                }
                cexception_finally (
                    {
                        delete_dnode( shared_arg );
                        const_value_free( (const_value_t*)&const_value );
                    },
                    { cexception_reraise( inner, ex ); }
                );
            }
            /* Insert the constant under the module parameter name: */
            if( argument_dnode ) {
                cexception_t inner;
                DNODE * volatile shared_argument_dnode = NULL;

                shared_argument_dnode = share_dnode( argument_dnode );
                dnode_insert_module_args( param, &shared_argument_dnode );

                shared_argument_dnode = share_dnode( argument_dnode );
                cexception_guard( inner ) {
                    vartab_insert( cc->consts, dnode_name( param ),
                                   &shared_argument_dnode, &inner );
                }
                cexception_catch {
                    delete_dnode( shared_argument_dnode );
                    cexception_reraise( inner, ex );
                }                    
            } else {
                yyerrorf( "constant '%s' is not found for module"
                          " parameter", argument_name );
            }
        } else if( tnode_kind( param_type ) == TK_VAR ||
                   tnode_kind( param_type ) == TK_FUNCTION ) {
            VARTAB *vartab =
                symtab_vartab( stlist_data( cc->symtab_stack ));
            DNODE *argument_dnode =
                vartab_lookup( vartab, argument_name );
            /* Insert the variable or function under the
               module parameter name: */
            if( argument_dnode ) {
                cexception_t inner;
                DNODE * volatile shared_argument_dnode = NULL;

                shared_argument_dnode = share_dnode( argument_dnode );
                dnode_insert_module_args( param, &shared_argument_dnode );

                shared_argument_dnode = share_dnode( argument_dnode );
                cexception_guard( inner ) {
                    vartab_insert( cc->vartab, dnode_name( param ),
                                   &shared_argument_dnode, &inner );
                }
                cexception_catch {
                    delete_dnode( shared_argument_dnode );
                    cexception_reraise( inner, ex );
                }
            } else {
                char *item_name =
                    tnode_kind( param_type ) == TK_VAR ?
                    "variable" : "function";
                if( argument_name ) {
                    yyerrorf( "%s '%s' is not found"
                              " for module parameter '%s'",
                              item_name, argument_name,
                              dnode_name( param ));
                } else {
                    yyerrorf( "%s is not found"
                              " for module parameter '%s'",
                              item_name, dnode_name( param ));
                }
            }
        } else {
            yyerrorf( "sorry, parameters of kind '%s' are not yet "
                      "supported for modules", 
                      tnode_kind_name( param_type ));
        }
        if( arg )
            arg = dnode_next( arg );
    } /* foreach_dnode( param, module_params ) { ... */
    if( arg ) {
        COMPILER_STATE *st = cc->include_files;
        char *filename = st ? st->filename : NULL;
        int line_no = st ? st->line_no : 0;
        if( filename ) {
            yyerrorf( "too many arguments for module '%s' "
                      "included from file '%s', line %d",
                      dnode_name( cc->requested_module ),
                      filename, line_no );
        } else {
            yyerrorf( "too many arguments for module '%s'",
                      dnode_name( cc->requested_module ));
        }
    }
}

static void compiler_insert_new_type( COMPILER *c, char *name, int not_null,
                                      TNODE* (*tnode_creator)( char *name, cexception_t *ex ),
                                      cexception_t *ex )
{
    TNODE *volatile tnode = (*tnode_creator)( name, ex );
    if( not_null ) {
        tnode_set_flags( tnode, TF_NON_NULL );
    }
    cexception_t inner;
    cexception_guard( inner ) {
        compiler_typetab_insert( c, &tnode, &inner );
    }
    cexception_catch {
        delete_tnode( tnode );
        cexception_reraise( inner, ex );
    }
}
 
static COMPILER * volatile compiler;

static cexception_t *px; /* parser exception */

%}

%union {
  long i;
  ssize_t si;          /* String index in the string pool */
  ANODE *anode;        /* type attribute description */
  TNODE *tnode;
  DNODE *dnode;
  ENODE *enode;
  TLIST *tlist;
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
%token _ARRAY
%token _AS
%token _ASSERT
%token _BLOB
%token _BREAK
%token _BYTECODE
%token _CATCH
%token _CLASS
%token _CLOSURE
%token _CONST
%token _CONSTRUCTOR
%token _CONTINUE
%token _DEBUG
%token _DESTRUCTOR
%token _DO
%token _ELSE
%token _ELSIF
%token _ENDDO
%token _ENDIF
%token _ENUM
%token _EXCEPTION
%token _FOR
%token _FORWARD
%token _FROM
%token _FUNCTION
%token _IF
%token _IMPLEMENTS
%token _IMPORT
%token _IN
%token _INCLUDE
%token _INLINE
%token _INTERFACE
%token _LIKE
%token _LOAD
%token _METHOD
%token _MODULE
%token _NATIVE
%token _NEW
%token _NOT
%token _NULL
%token _OF
%token _OPERATOR
%token _OTHERWISE
%token _PACK
%token _PACKAGE
%token _PRAGMA
%token _PROCEDURE
%token _PROGRAM
%token _RAISE
%token _READONLY
%token _REPEAT
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
%token _UNITS
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

%token <si> __ARITHM_ASSIGN  /* +=, -=, *=, etc. */

%token __QQ /* ?? */

%token <si> __IDENTIFIER
%token <si> __INTEGER_CONST
%token <si> __REAL_CONST
%token <si> __STRING_CONST

%type <dnode> argument
%type <dnode> argument_list
%type <dnode> closure_header
%type <dnode> closure_var_declaration
%type <dnode> closure_var_list_declaration
%type <c>     constant_expression
%type <i>     constant_integer_expression
%type <dnode> constructor_header
%type <dnode> constructor_definition
%type <tnode> dimension_list
%type <dnode> destructor_header
%type <dnode> destructor_definition
%type <dnode> enum_member
%type <tnode> enum_member_list
%type <i>     expression_list
%type <dnode> field_designator
%type <dnode> function_expression_header
%type <dnode> function_header
%type <dnode> method_definition
%type <dnode> method_header
%type <dnode> module_argument
%type <dnode> module_argument_list
%type <dnode> module_list
%type <i>     multivalue_function_call
%type <i>     multivalue_expression_list
%type <dnode> identifier
%type <dnode> identifier_list
%type <dnode> import_statement
%type <si>     include_statement
%type <i>     index_expression
%type <tnode> inheritance_and_implementation_list
%type <tlist> interface_identifier_list
%type <si>     labeled_for
%type <i>     lvalue_list
%type <i>     md_array_allocator
%type <dnode> module_import_identifier
%type <dnode> module_parameter
%type <dnode> module_parameter_list
%type <dnode> operator_definition
%type <dnode> operator_header
%type <si>     opt_as_identifier
%type <si>     opt_default_module_parameter
%type <si>     opt_dot_name
%type <si>     opt_identifier
%type <tnode> opt_method_interface
%type <i>     function_attributes
%type <dnode> function_definition
%type <i>     function_or_procedure_keyword
%type <i>     function_or_procedure_type_keyword
%type <si>     opt_closure_initialisation_list
%type <i>     opt_null_type_designator
%type <tnode> opt_base_type
%type <i>     opt_function_attributes
%type <i>     opt_function_or_procedure_keyword
%type <tlist> opt_implemented_interfaces
%type <si>     opt_label
%type <dnode> opt_module_arguments
%type <dnode> opt_module_parameters
%type <i>     opt_readonly
%type <dnode> opt_retval_description_list
%type <i>     opt_variable_declaration_keyword
%type <dnode> module_name
%type <dnode> program_header
%type <dnode> raised_exception_identifier;
%type <dnode> retval_description_list
%type <i>     size_constant
%type <tnode> struct_description
%type <tnode> struct_or_class_body
%type <tnode> interface_declaration_body
%type <tnode> interface_type_placeholder
%type <tnode> class_description
%type <dnode> struct_field
%type <tnode> struct_field_list
%type <dnode> struct_operator
%type <tnode> struct_operator_list
%type <dnode> struct_var_declaration
%type <dnode> interface_operator
%type <tnode> interface_operator_list
%type <tnode> compact_type_description
%type <si>     type_declaration_name
%type <tnode> type_identifier
%type <tnode> var_type_description
%type <tnode> undelimited_or_structure_description
%type <tnode> undelimited_type_description
%type <tnode> delimited_type_description
%type <anode> type_attribute
%type <dnode> use_statement
%type <dnode> variable_access_identifier
%type <dnode> variable_access_for_indexing
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

%left '@'

%left __COLON_COLON /* :: */

/* %left _AS */

%right __UNARY

%%

Program
  :   {
        ssize_t zero = 0;
        assert( compiler );
        compiler_insert_default_exceptions( compiler, px );
        compiler_compile_function_thrcode( compiler );
	compiler_push_absolute_fixup( compiler, px );
	compiler_emit( compiler, px, "\tce\n", ENTER, &zero );
	compiler_push_relative_fixup( compiler, px );
	compiler_emit( compiler, px, "\tce\n", JMP, &zero );
        compiler_compile_main_thrcode( compiler );
      }
    statement_list
      {
	compiler_compile_function_thrcode( compiler );
	compiler_fixup_here( compiler );
	compiler_fixup( compiler, -compiler->local_offset );
	compiler_merge_functions_and_main( compiler, px );
	compiler_check_forward_functions( compiler );
	compiler_emit( compiler, px, "\tc\n", NULL );
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
    { compiler_emit_drop_returned_values( compiler, $1, px ); }
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
  | program_definition
  | delimited_control_statement
  | module_statement
  | break_or_continue_statement
  | pack_statement
  | assert_statement
  | pragma_statement

  | /* empty statement */
  ;

assert_statement
  : _ASSERT expression
  {
    /*
    ssize_t current_line_no = compiler_flex_current_line_number();
    ssize_t file_name_offset = compiler_assemble_static_string
        ( compiler, compiler->filename, px );

    ssize_t current_line_offset = compiler_assemble_static_string
        ( compiler, (char*)compiler_flex_current_line(), px );
    */

    compiler_compile_unop( compiler, "assert", px );

    /*
    compiler_emit( compiler, px, "\tceee\n", ASSERT,
                &current_line_no, &file_name_offset, &current_line_offset );
    compiler_drop_top_expression( compiler );
    */
  }
  ;

/* pack a,    20,     4,    8;
   //-- blob, offset, size, value
*/
pack_statement
: _PACK expression ',' expression ',' expression ',' expression
{
    TNODE *type_to_pack = enode_type( compiler->e_stack );

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
		compiler_check_and_compile_operator( compiler, element_type,
						  "packmdarray", 4 /* arity */,
						  fixup_values, px );
	    } else {
		compiler_check_and_compile_operator( compiler, element_type,
						  "packarray", 4 /* arity */,
						  NULL /* fixup_values */, px );
	    }
	} else {
	    compiler_check_and_compile_operator( compiler, type_to_pack,
					      "pack", 4 /* arity */,
					  NULL /* fixup_values */, px );
	}
	compiler_emit( compiler, px, "\n" );
    } else {
	yyerrorf( "top expression has no type???" );
    }
}
;

break_or_continue_statement
  : _BREAK
    { compiler_compile_break( compiler, -1, px ); }
  | _BREAK __IDENTIFIER
    { compiler_compile_break( compiler, $2, px ); }
  | _CONTINUE
    { compiler_compile_continue( compiler, -1, px ); }
  | _CONTINUE __IDENTIFIER
    { compiler_compile_continue( compiler, $2, px ); }
  ;

undelimited_simple_statement
  : include_statement
       {
           char *volatile filename =
               obtain_string_from_strpool( compiler->strpool, $1 );
           cexception_t inner;

           cexception_guard( inner ) {
               compiler_open_include_file( compiler, filename, px );
           }
           cexception_catch {
               freex( filename );
               cexception_reraise( inner, px );
           }
           freex( filename );
       }
  | import_statement
       {
           if( yychar != YYEMPTY ) {
               /* fprintf( stderr, ">>> yacc: 'yyunget()' in 'import_statement'\n" ); */
               yyunget(); /* return the last read lexer token, which is a
                             look-ahead token, to the input stream. S.G.*/
               yyclearin; /* Discard the Bison look-ahead token. S.G. */
           }
           compiler_import_module( compiler, $1, px );
       }
  | use_statement
       {
           if( yychar != YYEMPTY ) {
               /* fprintf( stderr, ">>> yacc: 'yyunget()' in 'use_statement'\n" ); */
               yyunget(); /* return the last read lexer token, which is a
                             look-ahead token, to the input stream. S.G.*/
               yyclearin; /* Discard the Bison look-ahead token. S.G. */
           }
           compiler_use_module( compiler, $1, px );
       }
  | selective_use_statement
  | load_library_statement
  | bytecode_statement
  | function_definition
  | operator_definition
    {
#if 0
        printf( ">>>> receiving operator '%s', tnode name '%s'\n", dnode_name($1), tnode_name(dnode_type($1)));
#endif
        DNODE *volatile operator = $1;
        TNODE *optype = operator ? dnode_type( operator ) : NULL;
        char *opname = operator ? dnode_name( operator ) : NULL;

        if( optype && tnode_is_conversion( optype )) {
            opname = tnode_name( optype );
            if( opname && opname[0] == '@' ) {
                opname ++; /* Skip the '@' symbol */
            }
        }
#if 0
        printf( ">>>> inserting operator '%s'\n", opname );
#endif
        DNODE *volatile shared_operator = NULL;
        cexception_t inner;
        cexception_guard( inner ) {
            shared_operator = share_dnode( operator );
            vartab_insert_operator( compiler->operators, opname, &shared_operator, &inner );

            if( compiler->current_module && dnode_scope( operator ) == 0 ) {
                dnode_optab_insert_operator( compiler->current_module, opname,
                                             &operator, &inner );
            } else {
                dispose_dnode( &operator );
            }
        }
        cexception_catch {
            delete_dnode( shared_operator );
            delete_dnode( operator );
            cexception_reraise( inner, px );
        }
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
      compiler_push_thrcode( compiler, px );
    }
  ;

repeat_prefix
  : _REPEAT
    {
      compiler_push_loop( compiler, /* loop label = */ NULL,
                          /* ncounters = */ 0, px );
      compiler_push_current_address( compiler, px );
    }
  ;

non_control_statement_list
  : non_control_statement
  | non_control_statement_list ';' non_control_statement
  ;

delimited_control_statement
  : do_prefix non_control_statement_list
      {
	compiler_swap_thrcodes( compiler );
      }
    if_condition
      {
	compiler_merge_top_thrcodes( compiler, px );
        compiler_fixup_here( compiler );
      }

  | repeat_prefix 
      {
          compiler_begin_subscope( compiler, px );
      }
    non_control_statement_list _WHILE 
      {
	compiler_fixup_op_continue( compiler, px );
      }
    expression
      {
	compiler_compile_jnz( compiler, compiler_pop_offset( compiler, px ), px );
	compiler_fixup_op_break( compiler, px );
        compiler_pop_loop( compiler );
        compiler_end_subscope( compiler, px );
      }
  ;

raised_exception_identifier
  : __IDENTIFIER
      {
          char *name = obtain_string_from_strpool( compiler->strpool, $1 );
          $$ = compiler_lookup_dnode( compiler, NULL, name, "exception" );
          freex( name );
      }
  | module_list __COLON_COLON __IDENTIFIER
      {
          char *name = obtain_string_from_strpool( compiler->strpool, $3 );
          $$ = compiler_lookup_dnode( compiler, $1, name, "exception" );
          freex( name );
      }
  ;

raise_statement
  : _RAISE
    {
	ssize_t zero = 0;
	ssize_t minus_one = -1;
	compiler_emit( compiler, px, "\tce\n", LDC, &minus_one );
	compiler_emit( compiler, px, "\tc\n", PLDZ );
	compiler_emit( compiler, px, "\tcee\n", RAISE, &zero, &zero );
    }

  | _RAISE raised_exception_identifier
    {
	ssize_t zero = 0;
	ssize_t minus_one = -1;
	DNODE *exception = $2;
	ssize_t exception_val = exception ? dnode_ssize_value( exception ) : 0;

        if( exception ) {
            compiler_check_raise_expression( compiler, dnode_name( exception ),
                                             px );
        }

	compiler_emit( compiler, px, "\tce\n", LDC, &minus_one );
	compiler_emit( compiler, px, "\tc\n", PLDZ );
	compiler_emit( compiler, px, "\tcee\n", RAISE, &zero, &exception_val );
    }
  | _RAISE raised_exception_identifier '(' expression ')'
    {
	ssize_t zero = 0;
	DNODE *exception = $2;
	ssize_t exception_val = exception ? dnode_ssize_value( exception ) : 0;

        if( exception ) {
            compiler_check_raise_expression( compiler, dnode_name(exception),
                                             px );
        }

        if( tnode_is_reference( enode_type( compiler->e_stack ))) {
            compiler_emit( compiler, px, "\tce\n", LLDC, &zero );
            compiler_emit( compiler, px, "\tc\n", SWAP );            
        } else {
            compiler_emit( compiler, px, "\tc\n", PLDZ );
        }
        compiler_emit( compiler, px, "\tcee\n", RAISE, &zero, &exception_val );

	compiler_drop_top_expression( compiler );
    }

  | _RAISE raised_exception_identifier '(' expression ','
    {
        DNODE *exception = $2;

        if( exception ) {
            compiler_check_raise_expression( compiler, dnode_name(exception),
                                             px );
        }
	if( !compiler_stack_top_is_integer( compiler )) {
	    yyerrorf( "The first expression in 'raise' operator "
		      "must be of integer type" );
	}
    }
    expression ')'
    {
	ssize_t zero = 0;
	DNODE *exception = $2;
	ssize_t exception_val = exception ? dnode_ssize_value( exception ) : 0;

	if( !compiler_stack_top_is_reference( compiler )) {
	    yyerrorf( "The second expression in 'raise' operator "
		      "must be of string type" );
	}

	compiler_drop_top_expression( compiler );
	compiler_drop_top_expression( compiler );
	compiler_emit( compiler, px, "\tcee\n", RAISE, &zero, &exception_val );
    }

  | _RERAISE
    {
	if( !compiler->try_variable_stack || compiler->try_block_level < 1 ) {
	    yyerror( "'reraise' operator can only be used after "
		     "a try block" );
	} else {
	    ssize_t try_var_offset = compiler->try_variable_stack ?
		compiler->try_variable_stack[compiler->try_block_level-1] : 0;

	    compiler_emit( compiler, px, "\tce\n", RERAISE, &try_var_offset );
	}
    }
;

exception_declaration
  : _EXCEPTION __IDENTIFIER
    {
        char *name = obtain_string_from_strpool( compiler->strpool, $2 );
        compiler_compile_next_exception( compiler, name, px );
        freex( name );
    }
  ;

/*--------------------------------------------------------------------------*/
/* module and import statements */

module_name
  : __IDENTIFIER
      {
          char *volatile name = obtain_string_from_strpool( compiler->strpool, $1 );
          DNODE *volatile module_dnode = NULL;
          cexception_t inner;

          cexception_guard( inner ) {
              module_dnode = new_dnode_module( name, &inner );
          }
          cexception_finally (
              { freex( name ); },
              { cexception_reraise( inner, px ); }
          );
	  $$ = module_dnode;
      }
  ;

module_keyword : _PACKAGE | _MODULE;

opt_module_parameters
: /* empty */
    { $$ = NULL; }
| '(' module_parameter_list ')'
    { $$ = $2; }
;

module_parameter_list
: module_parameter
    { $$ = $1; }
| module_parameter_list ',' module_parameter
    { $$ = dnode_append( $1, $3 ); }
| module_parameter_list ';' module_parameter
    { $$ = dnode_append( $1, $3 ); }
;

module_parameter
: _TYPE __IDENTIFIER opt_default_module_parameter
    {
        $$ = compiler_module_parameter_dnode( compiler, $2, $3, TK_TYPE, px );
    }
| _PROCEDURE  __IDENTIFIER opt_default_module_parameter
    {
        $$ = compiler_module_parameter_dnode( compiler, $2, $3,
                                              TK_FUNCTION, px );
    }
| _FUNCTION __IDENTIFIER opt_default_module_parameter
    {
        $$ = compiler_module_parameter_dnode( compiler, $2, $3,
                                              TK_FUNCTION, px );
    }
| _CONST __IDENTIFIER opt_default_module_parameter
    {
        $$ = compiler_module_parameter_dnode( compiler, $2, $3, TK_CONST, px );
    }
| _VAR __IDENTIFIER opt_default_module_parameter
    {
        $$ = compiler_module_parameter_dnode( compiler, $2, $3, TK_VAR, px );
    }
| _OPERATOR __STRING_CONST opt_default_module_parameter
    {
        $$ = compiler_module_parameter_dnode( compiler, $2, $3, TK_OPERATOR, px );
    }
;

opt_default_module_parameter
: /* empty */
    { $$ = -1; }
| '=' __IDENTIFIER
    { $$ = $2; }
;

module_statement
  : module_keyword module_name opt_module_parameters
      {
          DNODE *volatile module_dnode = $2;
          DNODE *volatile shared_module_dnode = NULL;
          DNODE *module_params = $3;

          dnode_insert_module_args( module_dnode, &module_params );

          cexception_t inner;
          cexception_guard( inner ) {
              if( compiler->requested_module ) {
                  dnode_set_filename( module_dnode,
                                      dnode_filename( compiler->requested_module ),
                                      &inner );
              }

              shared_module_dnode = share_dnode( module_dnode );
              vartab_insert_named_module( compiler->vartab, &shared_module_dnode,
                                          stlist_data( compiler->symtab_stack ),
                                          &inner );

              if( compiler->current_module && dnode_scope( module_dnode ) == 0 ) {
                  shared_module_dnode = share_dnode( module_dnode );
                  dnode_vartab_insert_named_vars( compiler->current_module,
                                                  &shared_module_dnode,
                                                  &inner );
              }

              //compiler_begin_subscope( compiler, px );
              shared_module_dnode = share_dnode( module_dnode );
              compiler_begin_module( compiler, &shared_module_dnode, &inner );

              if( compiler->requested_module ) {
                  compiler_process_module_parameters
                      ( compiler, /*module_params*/
                        dnode_module_args( module_dnode ), &inner );
              }
          }
          cexception_catch {
              delete_dnode( module_dnode );
              delete_dnode( shared_module_dnode );
              cexception_reraise( inner, px );
          }
          delete_dnode( module_dnode );
      }
    statement_list '}' module_keyword __IDENTIFIER
      {
	  char *name;
	  if( compiler->current_module &&
	      (name = dnode_name( compiler->current_module )) != NULL ) {
              char *module_identifier =
                  obtain_string_from_strpool( compiler->strpool, $8 );
	      if( strcmp( module_identifier, name ) != 0 ) {
		  yyerrorf( "module '%s' ends with 'end module %s'",
			    name, module_identifier );
	      }
              freex( module_identifier );
	  }
	  compiler_end_module( compiler, px );
          //compiler_end_subscope( compiler, px );
      }
  ;

import_statement
   : _IMPORT module_import_identifier
       { $$ = $2; }
   ;

opt_module_arguments
: '(' module_argument_list ')'
    { $$ = $2; }
| /* empty */
    { $$ = NULL; }
;

module_argument_list
: module_argument
| module_argument_list ',' module_argument
   { $$ = dnode_append( $1, $3 ); }
;

module_argument
: identifier
| _CONST constant_expression
    { $$ = new_dnode_constant( /* name */ NULL, &$2, px ); }
| __INTEGER_CONST
    {
        char *int_string = obtain_string_from_strpool( compiler->strpool, $1 );
        intmax_t value = atol( int_string );
        freex( int_string );
        const_value_t cval = 
            make_const_value( px, VT_INTMAX, value );
        $$ = new_dnode_constant( /* name */ NULL, &cval, px );
    }

| __REAL_CONST
    {
        char *real_string = obtain_string_from_strpool( compiler->strpool, $1 );
        double value = atof( real_string );
        freex( real_string );
        const_value_t cval = make_const_value( px, VT_FLOAT, value );
        $$ = new_dnode_constant( /* name */ NULL, &cval, px );
    }

| __STRING_CONST
    {
        char *volatile string = obtain_string_from_strpool( compiler->strpool, $1 );
        cexception_t inner;
        cexception_guard( inner ) {
            /* cval now takes ownership of the string, no need to free
               it later: */
            const_value_t cval = make_const_value( &inner, VT_STRING, string );
            string = NULL;
            $$ = new_dnode_constant( /* name */ NULL, &cval, &inner );
        }
        cexception_catch {
            freex( string );
            cexception_reraise( inner, px );
        }
        freex( string );
    }
;

opt_as_identifier
:  _AS __IDENTIFIER
    { $$ = $2; }
| /* empty */
    { $$ = -1; }
;

module_import_identifier
  : __IDENTIFIER opt_module_arguments opt_as_identifier
  {
      cexception_t inner;
      char *volatile module_name =
          obtain_string_from_strpool( compiler->strpool, $1 );
      DNODE *module_name_dnode = NULL;
      DNODE *module_arguments = $2;
      char *volatile module_synonim =
          obtain_string_from_strpool( compiler->strpool, $3 );

      cexception_guard( inner ) {
          module_name_dnode = new_dnode_module( module_name, px );

          dnode_insert_module_args( module_name_dnode, &module_arguments );
          dnode_insert_synonim( module_name_dnode, &module_synonim );

          int count = 0;
          DNODE *existing_name = 
              vartab_lookup_silently( compiler->vartab, module_name, 
                                      &count, /* is_imported = */ NULL );
          if( !existing_name ) {
              char *pkg_path =
                  compiler_find_include_file
                  ( compiler,
                    compiler_find_module( compiler, module_name, &inner ),
                    &inner );
              dnode_set_filename( module_name_dnode, pkg_path, &inner );
#if 0
              printf( ">>> inserted filename '%s' for module '%s'\n",
                  pkg_path, dnode_name( module_name_dnode ));
#endif
          } else {
              char *filename = dnode_filename( existing_name );
              if( filename ) {
                  dnode_set_filename( module_name_dnode, filename, &inner );
#if 0
              printf( ">>> copying filename filename '%s' for module '%s'\n",
                  filename, dnode_name( module_name_dnode ));
#endif
              }
          }
      }
      cexception_catch {
          delete_dnode( module_name_dnode );
          freex( module_name );
          freex( module_synonim );
          cexception_reraise( inner, px );
      }

      freex( module_name );
      freex( module_synonim );
      $$ = module_name_dnode;
  }
  | __IDENTIFIER _IN __STRING_CONST opt_module_arguments opt_as_identifier
  {
      cexception_t inner;
      DNODE * volatile module_name_dnode = NULL;
      char *volatile module_name =
          obtain_string_from_strpool( compiler->strpool, $1 );
      char *volatile module_filename =
          obtain_string_from_strpool( compiler->strpool, $3 );
      DNODE *module_arguments = $4;
      char *volatile module_synonim =
          obtain_string_from_strpool( compiler->strpool, $5 );

      if( compiler->module_filename ) {
          freex( compiler->module_filename );
          compiler->module_filename = NULL;
      }
      cexception_guard( inner ) {
          module_name_dnode = new_dnode_module( module_name, &inner );
          compiler->module_filename = strdupx( module_filename, &inner );
          char *pkg_path =
              compiler_find_include_file( compiler, module_filename, &inner );
          dnode_set_filename( module_name_dnode, pkg_path, &inner );
      }
      cexception_catch {
          delete_dnode( module_name_dnode );
          freex( module_name );
          freex( module_filename );
          freex( module_synonim );
          cexception_reraise( inner, px );
      }
      dnode_insert_module_args( module_name_dnode, &module_arguments );
      dnode_insert_synonim( module_name_dnode, &module_synonim );

      freex( module_name );
      freex( module_filename );
      freex( module_synonim );
      $$ = module_name_dnode;
  }
;

use_statement
   : _USE module_import_identifier
       { $$ = $2; }
   | _USE '*' _FROM module_import_identifier
       { $$ = $4; }
   | _IMPORT '*' _FROM module_import_identifier
       { $$ = $4; }
   ;

selective_use_statement
   : _USE identifier_list _FROM /* module_import_identifier */ __IDENTIFIER
       {
           char *module_name =
               obtain_string_from_strpool( compiler->strpool, $4 );
           DNODE *imported_identifiers = $2;
           cexception_t inner;

           cexception_guard( inner ) {
               compiler_import_selected_names( compiler, &imported_identifiers,
                                               module_name, IMPORT_ALL,
                                               &inner );
           }
           cexception_catch {
               delete_dnode( imported_identifiers );
               freex( module_name );
               cexception_reraise( inner, px );
           }

           freex( module_name );
           delete_dnode( imported_identifiers );
       }

   | _USE _TYPE _ARRAY _FROM /* module_import_identifier */ __IDENTIFIER
       {
           char *volatile module_name =
               obtain_string_from_strpool( compiler->strpool, $5 );

           cexception_t inner;
           cexception_guard( inner ) {
               compiler_import_array_definition( compiler, module_name,
                                                 &inner );
           }
           cexception_catch {
               freex( module_name );
               cexception_reraise( inner, px );
           }
           freex( module_name );
       }
   | _IMPORT _TYPE _ARRAY _FROM /* module_import_identifier */ __IDENTIFIER
       {
           char *volatile module_name =
               obtain_string_from_strpool( compiler->strpool, $5 );

           cexception_t inner;
           cexception_guard( inner ) {
               compiler_import_array_definition( compiler, module_name,
                                                 &inner );
           }
           cexception_catch {
               freex( module_name );
               cexception_reraise( inner, px );
           }
           freex( module_name );
       }

   | _USE _TYPE identifier_list _FROM /* module_import_identifier */ __IDENTIFIER
       {
           DNODE *volatile imported_identifiers = $3;
           char *volatile module_name =
               obtain_string_from_strpool( compiler->strpool, $5 );

           cexception_t inner;
           cexception_guard( inner ) {
               compiler_import_type_identifier_list( compiler,
                                                     &imported_identifiers,
                                                     module_name, &inner );
           }
           cexception_catch {
               freex( module_name );
               delete_dnode( imported_identifiers );
               cexception_reraise( inner, px );
           }
           freex( module_name );
           delete_dnode( imported_identifiers );
       }
   | _IMPORT _TYPE identifier_list _FROM /* module_import_identifier */ __IDENTIFIER
       {
           DNODE *volatile imported_identifiers = $3;
           char *volatile module_name =
               obtain_string_from_strpool( compiler->strpool, $5 );

           cexception_t inner;
           cexception_guard( inner ) {
               compiler_import_type_identifier_list( compiler,
                                                     &imported_identifiers,
                                                     module_name, px );
           }
           cexception_catch {
               freex( module_name );
               delete_dnode( imported_identifiers );
               cexception_reraise( inner, px );
           }
           freex( module_name );
           delete_dnode( imported_identifiers );
       }

   | _USE _VAR identifier_list _FROM /* module_import_identifier */ __IDENTIFIER
       {
           DNODE *volatile imported_identifiers = $3;
           char *volatile module_name =
               obtain_string_from_strpool( compiler->strpool, $5 );

           cexception_t inner;
           cexception_guard( inner ) {
               compiler_import_selected_names( compiler, &imported_identifiers,
                                               module_name, IMPORT_VAR,
                                               &inner );

           }
           cexception_catch {
               freex( module_name );
               delete_dnode( imported_identifiers );
               cexception_reraise( inner, px );
           }
           freex( module_name );
           delete_dnode( imported_identifiers );
       }

   | _IMPORT _VAR identifier_list _FROM /* module_import_identifier */ __IDENTIFIER
       {
           char *volatile module_name =
               obtain_string_from_strpool( compiler->strpool, $5 );
           DNODE *volatile imported_identifiers = $3;

           cexception_t inner;
           cexception_guard( inner ) {
               compiler_import_selected_names( compiler, &imported_identifiers,
                                               module_name, IMPORT_VAR,
                                               &inner );
           }
           cexception_catch {
               freex( module_name );
               delete_dnode( imported_identifiers );
               cexception_reraise( inner, px );
           }
           freex( module_name );
           delete_dnode( imported_identifiers );
       }

   | _USE _CONST identifier_list _FROM /* module_import_identifier */ __IDENTIFIER
       {
           char *volatile module_name =
               obtain_string_from_strpool( compiler->strpool, $5 );
           DNODE *volatile imported_identifiers = $3;

           cexception_t inner;
           cexception_guard( inner ) {
               compiler_import_selected_constants( compiler,
                                                   &imported_identifiers,
                                                   module_name, &inner );
           }
           cexception_catch {
               freex( module_name );
               delete_dnode( imported_identifiers );
               cexception_reraise( inner, px );
           }
           freex( module_name );
           delete_dnode( imported_identifiers );
       }
   | _IMPORT _CONST identifier_list _FROM /* module_import_identifier */ __IDENTIFIER
       {
           char *volatile module_name =
               obtain_string_from_strpool( compiler->strpool, $5 );
           DNODE *volatile imported_identifiers = $3;

           cexception_t inner;
           cexception_guard( inner ) {
               compiler_import_selected_constants( compiler,
                                                   &imported_identifiers,
                                                   module_name, &inner );
           }
           cexception_catch {
               freex( module_name );
               delete_dnode( imported_identifiers );
               cexception_reraise( inner, px );
           }
           freex( module_name );
           delete_dnode( imported_identifiers );
       }

   | _USE function_or_procedure identifier_list
     _FROM /* module_import_identifier */  __IDENTIFIER
       {
           char *volatile module_name =
               obtain_string_from_strpool( compiler->strpool, $5 );
           DNODE *volatile imported_identifiers = $3;

           cexception_t inner;
           cexception_guard( inner ) {
               compiler_import_selected_names( compiler,
                                               &imported_identifiers,
                                               module_name, IMPORT_FUNCTION,
                                               &inner );
           }
           cexception_catch {
               freex( module_name );
               delete_dnode( imported_identifiers );
               cexception_reraise( inner, px );
           }
           freex( module_name );
           delete_dnode( imported_identifiers );
       }
   | _IMPORT function_or_procedure identifier_list 
     _FROM /* module_import_identifier */  __IDENTIFIER
       {
           char *volatile module_name =
               obtain_string_from_strpool( compiler->strpool, $5 );
           DNODE *volatile imported_identifiers = $3;

           cexception_t inner;
           cexception_guard( inner ) {
               compiler_import_selected_names( compiler,
                                               &imported_identifiers,
                                               module_name, IMPORT_FUNCTION,
                                               &inner );

           }
           cexception_catch {
               freex( module_name );
               delete_dnode( imported_identifiers );
               cexception_reraise( inner, px );
           }
           freex( module_name );
           delete_dnode( imported_identifiers );
       }
   ;

identifier
  : __IDENTIFIER
     {
         char *volatile name =
             obtain_string_from_strpool( compiler->strpool, $1 );

         cexception_t inner;
         cexception_guard( inner ) {
             $$ = new_dnode_name( name, &inner );
         }
         cexception_catch {
             freex( name );
             cexception_reraise( inner, px );
         }
         freex( name );
     }
  ;

identifier_list
   : identifier
     { $$ = $1; }
   | identifier_list ',' identifier
     { $$ = dnode_append( $1, $3 ); }
   ;

function_or_procedure: _FUNCTION | _PROCEDURE;

load_library_statement
   : _LOAD __STRING_CONST
       {
           char *volatile library_name =
               obtain_string_from_strpool( compiler->strpool, $2 );

           cexception_t inner;
           cexception_guard( inner ) {
               compiler_load_library( compiler, library_name,
                                      "SL_OPCODES", &inner );
           }
         cexception_catch {
             freex( library_name );
             cexception_reraise( inner, px );
         }
         freex( library_name );
       }
   ;

include_statement
   : _INCLUDE __STRING_CONST
       { $$ = $2; }
   ;

pragma_statement
: _PRAGMA type_identifier
   {
       TNODE *default_type = $2;

       if( default_type ) {
           typetab_override_suffix( compiler->typetab, /*name*/ "",
                                    TS_INTEGER_SUFFIX,
                                    &default_type, px );

           typetab_override_suffix( compiler->typetab, /*name*/ "",
                                    TS_FLOAT_SUFFIX, 
                                    &default_type, px );
       }
   }

| _PRAGMA __IDENTIFIER constant_expression
   {
       char *volatile pragma_name =
           obtain_string_from_strpool( compiler->strpool, $2 );

       cexception_t inner;
       cexception_guard( inner ) {
           if( const_value_type( &$3 ) == VT_INTMAX ) {
               long ival = const_value_integer( &$3 );
               compiler_set_integer_pragma( compiler, pragma_name, ival );
           } else {
               char *sval = const_value_string( &$3 );
               compiler_set_string_pragma( compiler, pragma_name,
                                           sval, &inner );
           }
       }
       cexception_catch {
           freex( pragma_name );
           cexception_reraise( inner, px );
       }
       freex( pragma_name );
   }

| _PRAGMA __IDENTIFIER _CONST type_identifier
   {
       TNODE *volatile default_type = $4;
       char *volatile type_kind_name =
           obtain_string_from_strpool( compiler->strpool, $2 );

       cexception_t inner;
       cexception_guard( inner ) {
           if( default_type ) {
               if( type_kind_name && strcmp( type_kind_name, "integer" ) == 0 ) {
                   typetab_override_suffix( compiler->typetab, /*name*/ "",
                                            TS_INTEGER_SUFFIX,
                                            &default_type, &inner );
               } else if( type_kind_name && 
                          strcmp( type_kind_name, "real" ) == 0 ) {
                   typetab_override_suffix( compiler->typetab, /*name*/ "",
                                            TS_FLOAT_SUFFIX, 
                                            &default_type, &inner );
               } else {
                   yyerror( "only \"integer\" and \"real\" constant kinds "
                            "can be assigned to default types by this pragma" );
               }
           }
       }
       cexception_catch {
           freex( type_kind_name );
           delete_tnode( default_type );
           cexception_reraise( inner, px );
       }
       assert( !default_type );
       freex( type_kind_name );
   }
;

opt_identifier
: __IDENTIFIER
| { $$ = strpool_add_string( compiler->strpool, "", px ); }
;

program_header
  :  _PROGRAM opt_identifier '(' argument_list ')' opt_retval_description_list
        {
	  cexception_t inner;
          char *volatile program_name =
              obtain_string_from_strpool( compiler->strpool, $2 );
	  DNODE *volatile funct = NULL;
          DNODE *retvals = $6;
          TNODE *retval_type = retvals ? dnode_type( retvals ) : NULL;
          ssize_t program_addr;

    	  cexception_guard( inner ) {
	      $$ = funct = new_dnode_function( program_name, $4, $6, &inner );
	      funct = $$ =
		  compiler_check_and_set_fn_proto( compiler, funct, &inner );

              compiler_check_and_emit_program_arguments( compiler, $4,
                                                         &inner );
              program_addr = thrcode_length( compiler->function_thrcode );
              compiler_emit( compiler, &inner, "\tce\n", CALL, &program_addr );
              /* Chech program return value; exit if the value is not zero: */
              if( retvals ) {
                  assert( retval_type );
                  compiler_emit( compiler, px, "\tc\n", DUP );
                  compiler_compile_constant( compiler, TS_INTEGER_SUFFIX,
                                          NULL, tnode_suffix( retval_type ), 
                                          "function return value", "0", px );
                  compiler_compile_operator( compiler, retval_type, "==", 2, px );
                  compiler_emit( compiler, px, "\n" );
                  compiler_emit( compiler, px, "\tcI\n", BJNZ, 6 );
                  compiler_emit( compiler, px, "\tcI\n", LDC, 0 );
                  compiler_compile_operator( compiler, retval_type,
                                          "nth-byte", 2, px );
                  compiler_emit( compiler, px, "\tc\n", EXIT );
                  compiler_emit( compiler, px, "\tc\n", DROP );
              }
	  }
	  cexception_catch {
              freex( program_name );
	      delete_dnode( $4 );
	      delete_dnode( $6 );
	      delete_dnode( funct );
	      $$ = NULL;
	      cexception_reraise( inner, px );
	  }
          freex( program_name );
	}
;

program_definition
:   program_header
    function_or_operator_start
    function_or_operator_body
    function_or_operator_end
  ;

module_list
: __IDENTIFIER
{
    char *module_name =
        obtain_string_from_strpool( compiler->strpool, $1 );
    DNODE *module;
    module = vartab_lookup( compiler->vartab, module_name );
    if( !module ) {
        yyerrorf( "module '%s' is not available in the current scope",
                  module_name );
    }
    $$ = module;
    freex( module_name );
}
| module_list __COLON_COLON __IDENTIFIER
{
    DNODE *container = $1;
    DNODE *module = NULL;
    char *module_name =
        obtain_string_from_strpool( compiler->strpool, $3 );
    if( container ) {
        module = dnode_vartab_lookup_var( container, module_name );
        if( !module ) {
            yyerrorf( "module '%s' is not available in as a submodule",
                      module_name );
        }
    }
    $$ = module;
    freex( module_name );
}
;

variable_access_identifier
  : __IDENTIFIER
     {
         char *ident =
             obtain_string_from_strpool( compiler->strpool, $1 );
	 $$ = compiler_lookup_dnode( compiler, NULL, ident, "variable" );
         freex( ident );
     }
  | module_list __COLON_COLON __IDENTIFIER
     {
         char *ident =
             obtain_string_from_strpool( compiler->strpool, $3 );
	 $$ = compiler_lookup_dnode( compiler, $1, ident, "variable" );
         freex( ident );
     }
  ;

incdec_statement
  : variable_access_identifier __INC
      {
          if( $1 && dnode_has_flags( $1, DF_IS_READONLY )) {
              yyerrorf( "may not increment readonly variable '%s'",
                        dnode_name( $1 ));
          } else {
              if( compiler_variable_has_operator( compiler, $1, "incvar", 0, px )) {
                  TNODE *var_type = dnode_type( $1 );
                  ssize_t var_offset = dnode_offset( $1 );

                  compiler_compile_operator( compiler, var_type, "incvar", 0, px );
                  compiler_emit( compiler, px, "eN\n", &var_offset, dnode_name( $1 ));
              } else {
                  compiler_compile_load_variable_value( compiler, $1, px );
                  compiler_compile_unop( compiler, "++", px );
                  compiler_compile_store_variable( compiler, $1, px );
              }
          }
      }
  | variable_access_identifier __DEC
      {
          if( $1 && dnode_has_flags( $1, DF_IS_READONLY )) {
              yyerrorf( "may not decrement readonly variable '%s'",
                        dnode_name( $1 ));
          } else {
              if( compiler_variable_has_operator( compiler, $1, "decvar", 0, px )) {
                  TNODE *var_type = dnode_type( $1 );
                  ssize_t var_offset = dnode_offset( $1 );

                  compiler_compile_operator( compiler, var_type, "decvar", 0, px );
                  compiler_emit( compiler, px, "eN\n", &var_offset, dnode_name( $1 ));
              } else {
                  compiler_compile_load_variable_value( compiler, $1, px );
                  compiler_compile_unop( compiler, "--", px );
                  compiler_compile_store_variable( compiler, $1, px );
              }
          }
      }
  | lvalue __INC
      {
	  compiler_compile_dup( compiler, px );
	  compiler_compile_ldi( compiler, px );
	  compiler_compile_unop( compiler, "++", px );
	  compiler_compile_sti( compiler, px );
      }
  | lvalue __DEC
      {
	  compiler_compile_dup( compiler, px );
	  compiler_compile_ldi( compiler, px );
	  compiler_compile_unop( compiler, "--", px );
	  compiler_compile_sti( compiler, px );
      }
  ;

print_expression_list
  : expression
      {
	  compiler_compile_unop( compiler, ".", px );
      }
  | print_expression_list ',' expression
      {
	  compiler_emit( compiler, px, "\tc\n", SPACE );
	  compiler_compile_unop( compiler, ".", px );
      }
; 

output_expression_list
  : expression
      {
	  compiler_compile_unop( compiler, "<", px );
      }
  | output_expression_list ',' expression
      {
	  compiler_emit( compiler, px, "\tc\n", SPACE );
	  compiler_compile_unop( compiler, "<", px );
      }
; 

io_statement
  : '.' print_expression_list
     {
	 compiler_emit( compiler, px, "\tc\n", NEWLINE );
     }

  | '<' output_expression_list

  | '>' lvariable
     {
	 compiler_compile_unop( compiler, ">", px );
     }

  | __RIGHT_TO_LEFT expression
     {
	 compiler_compile_unop( compiler, "<<", px );
     }

  | __LEFT_TO_RIGHT lvariable
     {
	 compiler_compile_unop( compiler, ">>", px );
     }

  | file_io_statement
    {
	compiler_emit( compiler, px, "\tc\n", PDROP );
	compiler_drop_top_expression( compiler );
    }

  | stdread_io_statement
  ;

stdread_io_statement
: '<' '>' __LEFT_TO_RIGHT variable_access_identifier
      {
          cexception_t inner;
          TNODE *type_tnode = typetab_lookup( compiler->typetab, "string" );

          cexception_guard( inner ) {
              compiler_push_typed_expression( compiler, type_tnode, &inner );
              compiler_emit( compiler, &inner, "\tc\n", STDREAD );
          }
          cexception_catch {
              delete_tnode( type_tnode );
              cexception_reraise( inner, px );
          }
          compiler_compile_store_variable( compiler, $4, px );
      }

  | '<' '>' __LEFT_TO_RIGHT lvalue
      {
          cexception_t inner;
          TNODE *type_tnode = typetab_lookup( compiler->typetab, "string" );

          cexception_guard( inner ) {
              compiler_push_typed_expression( compiler, type_tnode, &inner );
              compiler_emit( compiler, &inner, "\tc\n", STDREAD );
          }
          cexception_catch {
              delete_tnode( type_tnode );
              cexception_reraise( inner, px );
          }
          compiler_compile_sti( compiler, px );
      }
;

file_io_statement

  : '<' expression '>' __RIGHT_TO_LEFT expression
      {
       compiler_check_and_compile_top_operator( compiler, "<<", 2, px );
       compiler_emit( compiler, px, "\n" );
      }

  | '<' expression '>'
      {
	  compiler_push_thrcode( compiler, px );
      } 
    __LEFT_TO_RIGHT lvariable
      {
	  compiler_compile_file_input_operator( compiler, px );
      }

  | file_io_statement __RIGHT_TO_LEFT expression
      {
        compiler_check_and_compile_top_operator( compiler, "<<", 2, px );
        compiler_emit( compiler, px, "\n" );
      }

  | file_io_statement __LEFT_TO_RIGHT
      {
        compiler_push_thrcode( compiler, px );
      }
    lvariable
      {
	compiler_compile_file_input_operator( compiler, px );
      }
  ;

variable_declaration_keyword
  : _VAR { $$ = 0; }
  | _READONLY { $$ = 1; }
  | _READONLY _VAR { $$ = 1; }
  ;

opt_variable_declaration_keyword
  : variable_declaration_keyword
  | /* empty */
      { $$ = 0; }
;

variable_declaration
  : variable_declaration_keyword identifier ':' var_type_description
  {
      int readonly = $1;
      DNODE *volatile identifier_dnode = $2;
      DNODE *volatile shared_dnode = NULL;
      TNODE *volatile type_tnode = $4;
      cexception_t inner;

      cexception_guard( inner ) {
          dnode_list_append_type( identifier_dnode, type_tnode );
          type_tnode = NULL;
          dnode_list_assign_offsets( identifier_dnode,
                                     &compiler->local_offset );
          shared_dnode = share_dnode( identifier_dnode );
          compiler_vartab_insert_named_vars( compiler, &shared_dnode, &inner );
          if( readonly ) {
              dnode_list_set_flags( identifier_dnode, DF_IS_READONLY );
          }
          if( compiler->loops ) {
              compiler_compile_zero_out_stackcells( compiler, identifier_dnode,
                                                    &inner );
          }
          compiler_check_non_null_variables( identifier_dnode );
      }
      cexception_catch {
          delete_dnode( shared_dnode );
          delete_dnode( identifier_dnode );
          delete_tnode( type_tnode );
          cexception_reraise( inner, px );
      }
      delete_dnode( shared_dnode );
      delete_dnode( identifier_dnode );
      delete_tnode( type_tnode );
  }
  | variable_declaration_keyword 
    identifier ',' identifier_list ':' var_type_description
    {
     int readonly = $1;
     DNODE *volatile identifier_dnode = $2;
     DNODE *volatile shared_dnode = NULL;

     identifier_dnode = dnode_append( identifier_dnode, $4 );
     dnode_list_append_type( identifier_dnode, $6 );
     dnode_list_assign_offsets( identifier_dnode, &compiler->local_offset );

     cexception_t inner;
     cexception_guard( inner ) {
         shared_dnode = share_dnode( identifier_dnode );
         compiler_vartab_insert_named_vars( compiler, &shared_dnode, &inner );
         if( readonly ) {
             dnode_list_set_flags( identifier_dnode, DF_IS_READONLY );
         }
         if( compiler->loops ) {
             compiler_compile_zero_out_stackcells( compiler, identifier_dnode,
                                                   &inner );
         }
         compiler_check_non_null_variables( identifier_dnode );
     }
     cexception_catch {
         delete_dnode( identifier_dnode );
         delete_dnode( shared_dnode );
         cexception_reraise( inner, px );
     }
     delete_dnode( identifier_dnode );
     delete_dnode( shared_dnode );
    }

  | variable_declaration_keyword
    identifier ':' var_type_description initialiser
    {
     int readonly = $1;
     DNODE *volatile var = $2;
     DNODE *volatile shared_dnode = NULL;

     dnode_list_append_type( var, $4 );
     dnode_list_assign_offsets( var, &compiler->local_offset );

     cexception_t inner;
     cexception_guard( inner ) {
         shared_dnode = share_dnode( var );
         compiler_vartab_insert_named_vars( compiler, &var, &inner );
         if( readonly ) {
             dnode_list_set_flags( var, DF_IS_READONLY );
         }
         compiler_compile_initialise_variable( compiler, var, &inner );
     }
     cexception_catch {
         delete_dnode( var );
         delete_dnode( shared_dnode );
         cexception_reraise( inner, px );
     }
     delete_dnode( var );
     delete_dnode( shared_dnode );
    }

  | variable_declaration_keyword identifier ','
    identifier_list ':' var_type_description '=' multivalue_expression_list
    {
     int readonly = $1;
     DNODE *volatile identifier_dnode = $2;
     DNODE *volatile shared_dnode = NULL;
     int expr_nr = $8;

     identifier_dnode = dnode_append( identifier_dnode, $4 );
     dnode_list_append_type( identifier_dnode, $6 );
     dnode_list_assign_offsets( identifier_dnode, &compiler->local_offset );

     cexception_t inner;
     cexception_guard( inner ) {
         shared_dnode = share_dnode( identifier_dnode );
         compiler_vartab_insert_named_vars( compiler, &shared_dnode, px );
         if( readonly ) {
             dnode_list_set_flags( identifier_dnode, DF_IS_READONLY );
         }
         {
             DNODE *var;
             DNODE *lst = identifier_dnode;
             int len = dnode_list_length( lst );         

             if( expr_nr < len ) {
                 yyerrorf( "number of expressions (%d) is less "
                           "the number of variables (%d)", expr_nr, len );
             }

             if( expr_nr > len ) {
                 if( expr_nr == len + 1 ) {
                     compiler_compile_drop( compiler, px );
                 } else {
                     compiler_compile_dropn( compiler, expr_nr - len, px );
                 }
             }

             len = 0;
             foreach_reverse_dnode( var, lst ) {
                 len ++;
                 if( len <= expr_nr )
                     compiler_compile_initialise_variable( compiler, var, px );
             }
         }
     }
     cexception_catch {
         delete_dnode( identifier_dnode );
         delete_dnode( shared_dnode );
         cexception_reraise( inner, px );
     }
     delete_dnode( identifier_dnode );
     delete_dnode( shared_dnode );
    }

  | variable_declaration_keyword identifier ','
    identifier_list ':' var_type_description '=' simple_expression
    {
        yyerrorf( "need more than one expression to initialise %d variables",
                  dnode_list_length( $4 ) + 1 );

        $2 = dnode_append( $2, $4 );
        dnode_list_append_type( $2, $6 );
        dnode_list_assign_offsets( $2, &compiler->local_offset );
        compiler_vartab_insert_named_vars( compiler, &$2, px );
    }

  | variable_declaration_keyword var_type_description variable_declarator_list
      {
        int readonly = $1;
        DNODE *volatile var_list_dnode = $3;
        DNODE *volatile shared_dnode = NULL;

	dnode_list_append_type( var_list_dnode, $2 );
	dnode_list_assign_offsets( var_list_dnode, &compiler->local_offset );

        cexception_t inner;
        cexception_guard( inner ) {
            shared_dnode = share_dnode( var_list_dnode );
            compiler_vartab_insert_named_vars( compiler, &shared_dnode,
                                               &inner );
            if( readonly ) {
                dnode_list_set_flags( var_list_dnode, DF_IS_READONLY );
            }
            if( compiler->loops ) {
                compiler_compile_zero_out_stackcells( compiler, var_list_dnode,
                                                      &inner );
            }
            compiler_compile_variable_initialisations( compiler,
                                                       var_list_dnode,
                                                       &inner );
        }
        cexception_catch {
            delete_dnode( var_list_dnode );
            delete_dnode( shared_dnode );
            cexception_reraise( inner, px );
        }
        delete_dnode( var_list_dnode );
        delete_dnode( shared_dnode );
      }

  | variable_declaration_keyword identifier initialiser
    {
     TNODE *expr_type = compiler->e_stack ?
	 share_tnode( enode_type( compiler->e_stack )) : NULL;
     int readonly = $1;
     DNODE *volatile var = $2;
     DNODE *volatile shared_var = NULL;
     DNODE *volatile shared_args = NULL;
     DNODE *volatile shared_retvals = NULL;
     TNODE *volatile shared_base = NULL;

     type_kind_t expr_type_kind = expr_type ?
         tnode_kind( expr_type ) : TK_NONE;

     cexception_t inner;
     cexception_guard( inner ) {
         if( expr_type_kind == TK_FUNCTION ||
             expr_type_kind == TK_OPERATOR ||
             expr_type_kind == TK_METHOD ) {
             TNODE *base_type = typetab_lookup( compiler->typetab,
                                                "procedure" );
             shared_args = share_dnode( tnode_args( expr_type ));
             shared_retvals = share_dnode( tnode_retvals( expr_type ));
             shared_base = share_tnode( base_type );

             expr_type = new_tnode_function_or_proc_ref
                 ( shared_args, shared_retvals, shared_base, &inner );
             shared_args = shared_retvals = NULL;
             shared_base = NULL;
         }

         dnode_list_append_type( var, expr_type );
         dnode_list_assign_offsets( var, &compiler->local_offset );

         shared_var = share_dnode( var );
         compiler_vartab_insert_named_vars( compiler, &shared_var, &inner );
         if( readonly ) {
             dnode_list_set_flags( var, DF_IS_READONLY );
         }
         compiler_compile_initialise_variable( compiler, var, &inner );
     }
     cexception_finally (
         {
             delete_dnode( var );
             delete_dnode( shared_var );
             delete_dnode( shared_args );
             delete_dnode( shared_retvals );
             delete_tnode( shared_base );
         },
         {
             cexception_reraise( inner, px );
         }
     )
    }
 
 | variable_declaration_keyword identifier ','
    identifier_list '=' multivalue_expression_list
    {
     int readonly = $1;
     DNODE *volatile ident_dnode = $2;
     DNODE *volatile shared_dnode = NULL;
     DNODE *volatile shared_args = NULL;
     DNODE *volatile shared_retvals = NULL;
     TNODE *volatile shared_base = NULL;
     TNODE *volatile expr_type = NULL;
     cexception_t inner;

     cexception_guard( inner ) {
         ident_dnode = dnode_append( ident_dnode, $4 );
         dnode_list_assign_offsets( ident_dnode, &compiler->local_offset );
         shared_dnode = share_dnode( ident_dnode );
         compiler_vartab_insert_named_vars( compiler, &shared_dnode, &inner );
         if( readonly ) {
             dnode_list_set_flags( ident_dnode, DF_IS_READONLY );
         }
         {
             DNODE *var;
             DNODE *lst = ident_dnode;
             ssize_t len = dnode_list_length( lst );
             ssize_t expr_nr = $6;

             if( expr_nr < len ) {
                 yyerrorf( "number of expressions (%d) is less than "
                           "is needed to initialise %d variables",
                           expr_nr, len );
             }

             if( expr_nr > len ) {
                 if( expr_nr == len + 1 ) {
                     compiler_compile_drop( compiler, &inner );
                 } else {
                     compiler_compile_dropn( compiler, expr_nr - len, &inner );
                 }
             }

             len = 0;
             foreach_reverse_dnode( var, lst ) {
                 len ++;
                 expr_type = compiler->e_stack ?
                     share_tnode( enode_type( compiler->e_stack )) : NULL;
                 type_kind_t expr_type_kind = expr_type ?
                     tnode_kind( expr_type ) : TK_NONE;
                 if( expr_type_kind == TK_FUNCTION ||
                     expr_type_kind == TK_OPERATOR ||
                     expr_type_kind == TK_METHOD ) {
                     shared_base = share_tnode( typetab_lookup( compiler->typetab,
                                                                "procedure" ));

                     shared_args = share_dnode( tnode_args( expr_type ));
                     shared_retvals = share_dnode( tnode_retvals( expr_type ));

                     expr_type = new_tnode_function_or_proc_ref
                         ( shared_args, shared_retvals, shared_base, &inner );
                     shared_args = shared_retvals = NULL;
                     shared_base = NULL;
                 }
                 dnode_append_type( var, expr_type );
                 expr_type = NULL;
                 if( len <= expr_nr )
                     compiler_compile_initialise_variable( compiler, var, &inner );
             }
         }
     }
     cexception_finally(
         {
             delete_dnode( ident_dnode );
             delete_dnode( shared_dnode );
             delete_dnode( shared_args );
             delete_dnode( shared_retvals );
             delete_tnode( shared_base );
             delete_tnode( expr_type );
         },
         {
             cexception_reraise( inner, px );
         }
     )
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
  : identifier
  | identifier dimension_list
      { $$ = dnode_insert_type( $1, $2 ); }
  ;

return_statement
  : _RETURN
      {
	compiler_push_guarding_retval( compiler, px );
	compiler_compile_return( compiler, 0, px );
      }
  | _RETURN 
      {
	if( compiler->loops ) {
            char *name = dnode_name( compiler->loops );
	    compiler_drop_loop_counters( compiler, name, 0, px );
	}
        compiler_push_guarding_retval( compiler, px );
      }
    expression_list
      { compiler_compile_return( compiler, $3, px ); }
  ;

/*--------------------------------------------------------------------------*/

opt_label
  : __IDENTIFIER ':'
      { $$ = $1; }
  |
      { $$ = -1; }
  ;

if_condition
  : _IF /* expression */ {} condition
      {
        compiler_push_relative_fixup( compiler, px );
	compiler_compile_jz( compiler, 0, px );
      }
  ;

for_variable_declaration
  : identifier ':' var_type_description
      {
	  dnode_append_type( $1, $3 );
	  dnode_assign_offset( $1, &compiler->local_offset );
	  $$ = $1;
      }
  | var_type_description identifier
      {
	  dnode_append_type( $2, $1 );
	  dnode_assign_offset( $2, &compiler->local_offset );
	  $$ = $2;
      }
  | identifier
      {
	  $$ = $1;
      }
  ;

elsif_condition
  : _ELSIF /* expression */ {} condition
      {
        compiler_push_relative_fixup( compiler, px );
	compiler_compile_jz( compiler, 0, px );
      }
  ;

elsif_statement
  : elsif_condition _THEN statement_list _ENDIF
    {
        compiler_fixup_here( compiler );
    }

  | elsif_condition _THEN statement_list
    {
	ssize_t zero = 0;
        compiler_push_relative_fixup( compiler, px );
        compiler_emit( compiler, px, "\tce\n", JMP, &zero );
        compiler_swap_fixups( compiler );
        compiler_fixup_here( compiler );
    }
    elsif_statement
    {
        compiler_fixup_here( compiler );
    }

  | elsif_condition _THEN statement_list
    {
	ssize_t zero = 0;
        compiler_push_relative_fixup( compiler, px );
        compiler_emit( compiler, px, "\tce\n", JMP, &zero );
        compiler_swap_fixups( compiler );
        compiler_fixup_here( compiler );
    }
    _ELSE statement_list _ENDIF
    {
        compiler_fixup_here( compiler );
    }
;

otherwise_condition
  : _OTHERWISE _IF /* expression */ {} condition
      {
        compiler_push_relative_fixup( compiler, px );
	compiler_compile_jz( compiler, 0, px );
      }
  ;

otherwise_branch
:   otherwise_condition compound_statement
      {
        compiler_fixup_here( compiler );
      }

  | otherwise_condition compound_statement
      {
	ssize_t zero = 0;
        compiler_push_relative_fixup( compiler, px );
        compiler_emit( compiler, px, "\tce\n", JMP, &zero );
        compiler_swap_fixups( compiler );
        compiler_fixup_here( compiler );
      }
    otherwise_branch
      {
        compiler_fixup_here( compiler );
      }

  | otherwise_condition compound_statement _ELSE 
      {
	ssize_t zero = 0;
        compiler_push_relative_fixup( compiler, px );
        compiler_emit( compiler, px, "\tce\n", JMP, &zero );
        compiler_swap_fixups( compiler );
        compiler_fixup_here( compiler );
      }
    compound_statement
      {
        compiler_fixup_here( compiler );
      }
;

labeled_for
: opt_label _FOR
      {
	compiler_begin_subscope( compiler, px );
        $$ = $1;
      }
;

in_loop_separator : __THICK_ARROW | _IN ;

control_statement
  : if_condition _THEN statement_list _ENDIF
      {
        compiler_fixup_here( compiler );
      }

  | if_condition _THEN statement_list
      {
	ssize_t zero = 0;
        compiler_push_relative_fixup( compiler, px );
        compiler_emit( compiler, px, "\tce\n", JMP, &zero );
        compiler_swap_fixups( compiler );
        compiler_fixup_here( compiler );
      }
    _ELSE statement_list _ENDIF
      {
        compiler_fixup_here( compiler );
      }

  | if_condition _THEN statement_list
      {
	ssize_t zero = 0;
        compiler_push_relative_fixup( compiler, px );
        compiler_emit( compiler, px, "\tce\n", JMP, &zero );
        compiler_swap_fixups( compiler );
        compiler_fixup_here( compiler );
      }
    elsif_statement
      {
        compiler_fixup_here( compiler );
      }

  | if_condition compound_statement
      {
        compiler_fixup_here( compiler );
      }

  | if_condition compound_statement _ELSE 
      {
	ssize_t zero = 0;
        compiler_push_relative_fixup( compiler, px );
        compiler_emit( compiler, px, "\tce\n", JMP, &zero );
        compiler_swap_fixups( compiler );
        compiler_fixup_here( compiler );
      }
    compound_statement
      {
        compiler_fixup_here( compiler );
      }

  | if_condition compound_statement
      {
	ssize_t zero = 0;
        compiler_push_relative_fixup( compiler, px );
        compiler_emit( compiler, px, "\tce\n", JMP, &zero );
        compiler_swap_fixups( compiler );
        compiler_fixup_here( compiler );
      }
    otherwise_branch
      {
        compiler_fixup_here( compiler );
      }

  | opt_label _WHILE
      {
	  ssize_t zero = 0;
          char *volatile loop_label =
              obtain_string_from_strpool( compiler->strpool, $1 );

          cexception_t inner;
          cexception_guard( inner ) {
              compiler_begin_subscope( compiler, &inner );
              compiler_push_loop( compiler, loop_label, 0, &inner );
              compiler_push_relative_fixup( compiler, &inner );
              compiler_emit( compiler, &inner, "\tce\n", JMP, &zero );
              compiler_push_current_address( compiler, &inner );
              compiler_push_thrcode( compiler, &inner );
          }
          cexception_catch {
              freex( loop_label );
              cexception_reraise( inner, px );
          }
          freex( loop_label );
      }
    condition
      {
	compiler_swap_thrcodes( compiler );
      }
    loop_body
      {
        compiler_fixup_here( compiler );
	compiler_fixup_op_continue( compiler, px );
	compiler_merge_top_thrcodes( compiler, px );
	compiler_compile_jnz( compiler, compiler_pop_offset( compiler, px ), px );
	compiler_fixup_op_break( compiler, px );
	compiler_pop_loop( compiler );
        compiler_end_subscope( compiler, px );
      }

  | labeled_for '(' statement ';'
      {
          char *volatile loop_label =
              obtain_string_from_strpool( compiler->strpool, $1 );

          cexception_t inner;
          cexception_guard( inner ) {
              compiler_push_loop( compiler, loop_label, 0, &inner );
              compiler_push_thrcode( compiler, &inner );
          }
          cexception_catch {
              freex( loop_label );
              cexception_reraise( inner, px );
          }
          freex( loop_label );
      }
    condition ';'
      {
	compiler_push_thrcode( compiler, px );
      }
    statement ')'
      {
        ssize_t zero = 0;
	compiler_push_thrcode( compiler, px );
        compiler_push_relative_fixup( compiler, px );
	compiler_emit( compiler, px, "\tce\n", JMP, &zero );
      }
    loop_body
      {
	compiler_fixup_op_continue( compiler, px );
	compiler_merge_top_thrcodes( compiler, px );

        compiler_fixup_here( compiler );
	compiler_merge_top_thrcodes( compiler, px );

	compiler_compile_jnz( compiler, -compiler_code_length( compiler ) + 2, px );

	compiler_swap_thrcodes( compiler );
	compiler_merge_top_thrcodes( compiler, px );
	compiler_fixup_op_break( compiler, px );
	compiler_pop_loop( compiler );
	compiler_end_subscope( compiler, px );
      }

  | labeled_for lvariable
      {
          char *volatile loop_label =
              obtain_string_from_strpool( compiler->strpool, $1 );

          cexception_t inner;
          cexception_guard( inner ) {
              compiler_push_loop( compiler, loop_label, 2, &inner );
              dnode_set_flags( compiler->loops, DF_LOOP_HAS_VAL );
              compiler_compile_dup( compiler, &inner );
          }
          cexception_catch {
              freex( loop_label );
              cexception_reraise( inner, px );
          }
          freex( loop_label );
      }
    '=' expression
      {
        compiler_compile_sti( compiler, px );
      }
    _TO expression
      {
	compiler_compile_over( compiler, px );
	compiler_compile_ldi( compiler, px );
	compiler_compile_over( compiler, px );
	if( compiler_test_top_types_are_identical( compiler, px )) {
	    compiler_compile_binop( compiler, ">", px );
	    compiler_push_relative_fixup( compiler, px );
	    compiler_compile_jnz( compiler, 0, px );
	} else {
	    ssize_t zero = 0;
	    compiler_drop_top_expression( compiler );
	    compiler_drop_top_expression( compiler );
	    compiler_push_relative_fixup( compiler, px );
	    compiler_emit( compiler, px, "\tce\n", JMP, &zero );
	}

        compiler_push_current_address( compiler, px );
      }
     loop_body
      {
	compiler_fixup_here( compiler );
	compiler_fixup_op_continue( compiler, px );
	compiler_compile_loop( compiler, compiler_pop_offset( compiler, px ), px );
	compiler_fixup_op_break( compiler, px );
	compiler_pop_loop( compiler );
	compiler_end_subscope( compiler, px );
      }

  | labeled_for variable_declaration_keyword for_variable_declaration
      {
          char *volatile loop_label =
              obtain_string_from_strpool( compiler->strpool, $1 );
          int readonly = $2;

          cexception_t inner;
          cexception_guard( inner ) {
              if( readonly ) {
                  dnode_set_flags( $3, DF_IS_READONLY );
              }
              compiler_push_loop( compiler, loop_label, 2, &inner );
              dnode_set_flags( compiler->loops, DF_LOOP_HAS_VAL );
          }
          cexception_catch {
              freex( loop_label );
              cexception_reraise( inner, px );
          }
          freex( loop_label );
      }
    '=' expression
      {
	DNODE *volatile loop_counter = $3;
        DNODE *volatile shared_counter = NULL;

        cexception_t inner;
        cexception_guard( inner ) {
            if( dnode_type( loop_counter ) == NULL ) {
                dnode_append_type( loop_counter,
                                   share_tnode( enode_type( compiler->e_stack )));
                dnode_assign_offset( loop_counter, &compiler->local_offset );
            }
            shared_counter = share_dnode( loop_counter );
            compiler_vartab_insert_named_vars( compiler, &shared_counter,
                                               &inner );
            compiler_compile_store_variable( compiler, loop_counter, &inner );
            compiler_compile_load_variable_address( compiler, loop_counter, &inner );
        }
        cexception_catch {
            delete_dnode( loop_counter );
            delete_dnode( shared_counter );
            cexception_reraise( inner, px );
        }
        delete_dnode( loop_counter );
        delete_dnode( shared_counter );
      }
    _TO expression
      {
	compiler_compile_over( compiler, px );
	compiler_compile_ldi( compiler, px );
	compiler_compile_over( compiler, px );
	if( compiler_test_top_types_are_identical( compiler, px )) {
	    compiler_compile_binop( compiler, ">", px );
	    compiler_push_relative_fixup( compiler, px );
	    compiler_compile_jnz( compiler, 0, px );
	} else {
	    ssize_t zero = 0;
	    compiler_drop_top_expression( compiler );
	    compiler_drop_top_expression( compiler );
	    compiler_push_relative_fixup( compiler, px );
	    compiler_emit( compiler, px, "\tce\n", JMP, &zero );
	}

        compiler_push_current_address( compiler, px );
      }
     loop_body
      {
	compiler_fixup_here( compiler );
	compiler_fixup_op_continue( compiler, px );
	compiler_compile_loop( compiler, compiler_pop_offset( compiler, px ), px );
	compiler_fixup_op_break( compiler, px );
	compiler_pop_loop( compiler );
	compiler_end_subscope( compiler, px );
      }

  | labeled_for variable_declaration_keyword for_variable_declaration
      {
          char *volatile loop_label =
              obtain_string_from_strpool( compiler->strpool, $1 );
          int readonly = $2;

          cexception_t inner;
          cexception_guard( inner ) {
              if( readonly ) {
                  dnode_set_flags( $3, DF_IS_READONLY );
              }
              compiler_push_loop( compiler, loop_label,
                                  /* ncounters = */ 1, &inner );
              dnode_set_flags( compiler->loops, DF_LOOP_HAS_VAL );
          }
          cexception_catch {
              freex( loop_label );
              cexception_reraise( inner, px );
          }
          freex( loop_label );
      }
    _IN expression
      {
	DNODE *volatile loop_counter_var = $3;
	DNODE *volatile shared_loop_counter = NULL;
        TNODE *aggregate_expression_type = enode_type( compiler->e_stack );
        TNODE *element_type = 
            aggregate_expression_type ?
            tnode_element_type( aggregate_expression_type ) : NULL;
        ssize_t neg_element_size = -1;
        ssize_t zero = 0;

        if( enode_has_flags( compiler->e_stack, EF_IS_READONLY )) {
	    dnode_set_flags( loop_counter_var, DF_IS_READONLY );
        }

        /* stack now: ..., array_current_ptr */
        if( element_type ) {
            if( dnode_type( loop_counter_var ) == NULL ) {
                dnode_append_type( loop_counter_var,
                                   share_tnode( element_type ));
            }
            dnode_assign_offset( loop_counter_var,
                                 &compiler->local_offset );
        }

        cexception_t inner;
        cexception_guard( inner ) {
            shared_loop_counter = share_dnode( loop_counter_var );
            compiler_vartab_insert_named_vars( compiler, &shared_loop_counter,
                                               &inner );

            compiler_emit( compiler, &inner, "\tce\n", OFFSET, &neg_element_size );

            compiler_push_relative_fixup( compiler, &inner );
            compiler_emit( compiler, &inner, "\tce\n", JMP, &zero );

            compiler_push_current_address( compiler, &inner );

            /* stack now: ..., array_current_ptr */
            /* Store the current array element into the loop variable: */
            compiler_compile_dup( compiler, &inner );
            compiler_make_stack_top_element_type( compiler );
            compiler_make_stack_top_addressof( compiler, &inner );
            if( aggregate_expression_type &&
                tnode_kind( aggregate_expression_type ) == TK_ARRAY &&
                element_type &&
                tnode_kind( element_type ) != TK_PLACEHOLDER ) {
                compiler_compile_ldi( compiler, &inner );
            } else {
                compiler_emit( compiler, &inner, "\tc\n", GLDI );
                compiler_stack_top_dereference( compiler );
            }
            compiler_compile_variable_initialisation
                ( compiler, loop_counter_var, &inner );

        }
        cexception_catch {
            delete_dnode( shared_loop_counter );
            delete_dnode( loop_counter_var );
            cexception_reraise( inner, px );
        }
        delete_dnode( loop_counter_var );
      }
     loop_body
      {
	int readonly = $2;
	DNODE *loop_counter_var = $3;
        /* stack now: ..., array_current_ptr */

        /* Store the the loop variable back into the current array element: */
        if( !readonly ) {
            TNODE *aggregate_expression_type = enode_type( compiler->e_stack );
            TNODE *element_type = 
                aggregate_expression_type ?
                tnode_element_type( aggregate_expression_type ) : NULL;

            compiler_compile_dup( compiler, px );
            compiler_make_stack_top_element_type( compiler );
            compiler_make_stack_top_addressof( compiler, px );
            compiler_compile_load_variable_value( compiler,
                                                  loop_counter_var, px );
            if( aggregate_expression_type &&
                tnode_kind( aggregate_expression_type ) == TK_ARRAY &&
                tnode_kind( element_type ) != TK_PLACEHOLDER ) {
                compiler_compile_sti( compiler, px );
            } else {
                compiler_emit( compiler, px, "\tc\n", GSTI );
                compiler_drop_top_expression( compiler );
                compiler_drop_top_expression( compiler );
            }
        }

	compiler_fixup_op_continue( compiler, px );
        compiler_fixup_here( compiler );
	compiler_compile_next( compiler, compiler_pop_offset( compiler, px ),
                               px );

	compiler_fixup_op_break( compiler, px );
	compiler_pop_loop( compiler );
	compiler_end_subscope( compiler, px );
      }

  | labeled_for lvariable _IN
      {
          char *volatile loop_label =
              obtain_string_from_strpool( compiler->strpool, $1 );

          cexception_t inner;
          cexception_guard( inner ) {
              compiler_push_loop( compiler, loop_label,
                                  /* ncounters = */ 2, &inner );
              dnode_set_flags( compiler->loops, DF_LOOP_HAS_VAL );
          }
          cexception_catch {
              freex( loop_label );
              cexception_reraise( inner, px );
          }
          freex( loop_label );
          /* stack now: ..., lvariable_address */
      }
    expression
      {
        /* stack now:
           ..., lvariable_address, array_last_ptr */
        ssize_t neg_element_size = -1;
        ssize_t zero = 0;

        /* stack now: ..., lvariable_address, array_current_ptr */

        compiler_emit( compiler, px, "\tce\n", OFFSET, &neg_element_size );

        compiler_push_relative_fixup( compiler, px );
        compiler_emit( compiler, px, "\tce\n", JMP, &zero );

        /* The execution flow should return here after each iteration: */
        compiler_push_current_address( compiler, px );

        /* stack now: ..., lvariable_address, array_current_ptr */
        /* Store the current array element into the loop variable: */
        compiler_compile_over( compiler, px );
        compiler_compile_over( compiler, px );
        compiler_make_stack_top_element_type( compiler );
        compiler_make_stack_top_addressof( compiler, px );
        compiler_compile_ldi( compiler, px );
        compiler_compile_sti( compiler, px );
      }
     loop_body
      {
        /* stack now:
           ..., lvariable_address, array_current_ptr */
        ENODE *loop_var = compiler->e_stack; /* array_current_ptr */
        loop_var = loop_var ? enode_next( loop_var ) : NULL; /* lvariable_address */
        
        if( loop_var && !enode_has_flags( loop_var, EF_IS_READONLY )) {
            /* Store the current array element into the loop variable: */
            /* stack now:
               ..., lvariable_address, array_current_ptr */
            compiler_compile_over( compiler, px );
            compiler_compile_over( compiler, px );
            compiler_make_stack_top_element_type( compiler );
            compiler_make_stack_top_addressof( compiler, px );
            compiler_compile_swap( compiler, px );
            compiler_compile_ldi( compiler, px );
            compiler_compile_sti( compiler, px );
        }

	compiler_fixup_op_continue( compiler, px );
	compiler_fixup_here( compiler );
	compiler_compile_next( compiler, compiler_pop_offset( compiler, px ),
                               px );

	compiler_fixup_op_break( compiler, px );
	compiler_pop_loop( compiler );
      }

  | labeled_for '(' variable_declaration_keyword for_variable_declaration
      {
          char *volatile loop_label =
              obtain_string_from_strpool( compiler->strpool, $1 );
	int readonly = $3;

        cexception_t inner;
        cexception_guard( inner ) {
            if( readonly ) {
                dnode_set_flags( $4, DF_IS_READONLY );
            }
            compiler_push_loop( compiler, loop_label,
                                /* ncounters = */ 1, &inner );
            dnode_set_flags( compiler->loops, DF_LOOP_HAS_VAL );
        }
        cexception_catch {
            freex( loop_label );
            cexception_reraise( inner, px );
        }
        freex( loop_label );
      }
    in_loop_separator expression ')'
      {
	DNODE *volatile loop_counter_var = $4;
	DNODE *volatile shared_loop_counter = NULL;
        TNODE *aggregate_expression_type = enode_type( compiler->e_stack );
        TNODE *element_type = 
            aggregate_expression_type ?
            tnode_element_type( aggregate_expression_type ) : NULL;
        ssize_t neg_element_size = -1;
        ssize_t zero = 0;

        if( enode_has_flags( compiler->e_stack, EF_IS_READONLY )) {
	    dnode_set_flags( loop_counter_var, DF_IS_READONLY );
        }

        /* stack now: ..., array_current_ptr */
        if( element_type ) {
            if( dnode_type( loop_counter_var ) == NULL ) {
                dnode_append_type( loop_counter_var,
                                   share_tnode( element_type ));
            }
            dnode_assign_offset( loop_counter_var,
                                 &compiler->local_offset );
        }

        cexception_t inner;
        cexception_guard( inner ) {
            shared_loop_counter = share_dnode( loop_counter_var );

            compiler_vartab_insert_named_vars( compiler, &shared_loop_counter,
                                               &inner );

            compiler_emit( compiler, &inner, "\tce\n", OFFSET,
                           &neg_element_size );

            compiler_push_relative_fixup( compiler, &inner );
            compiler_emit( compiler, &inner, "\tce\n", JMP, &zero );

            compiler_push_current_address( compiler, &inner );

            /* stack now: ..., array_current_ptr */
            /* Store the current array element into the loop variable: */
            compiler_compile_dup( compiler, &inner );
            compiler_make_stack_top_element_type( compiler );
            compiler_make_stack_top_addressof( compiler, &inner );
            if( aggregate_expression_type &&
                tnode_kind( aggregate_expression_type ) == TK_ARRAY &&
                tnode_kind( element_type ) != TK_PLACEHOLDER ) {
                compiler_compile_ldi( compiler, &inner );
            } else {
                compiler_emit( compiler, &inner, "\tc\n", GLDI );
                compiler_stack_top_dereference( compiler );
            }
            compiler_compile_variable_initialisation
                ( compiler, loop_counter_var, &inner );
        }
        cexception_catch {
            delete_dnode( loop_counter_var );
            delete_dnode( shared_loop_counter );
            cexception_reraise( inner, px );
        }
        delete_dnode( loop_counter_var );
        delete_dnode( shared_loop_counter );
      }
     loop_body
      {
	int readonly = $3;
	DNODE *loop_counter_var = $4;
        /* stack now: ..., array_current_ptr */

        /* Store the the loop variable back into the current array element: */
        if( !readonly ) {
            TNODE *aggregate_expression_type = enode_type( compiler->e_stack );
            TNODE *element_type = 
                aggregate_expression_type ?
                tnode_element_type( aggregate_expression_type ) : NULL;

            compiler_compile_dup( compiler, px );
            compiler_make_stack_top_element_type( compiler );
            compiler_make_stack_top_addressof( compiler, px );
            compiler_compile_load_variable_value( compiler,
                                                  loop_counter_var, px );
            if( aggregate_expression_type &&
                tnode_kind( aggregate_expression_type ) == TK_ARRAY &&
                tnode_kind( element_type ) != TK_PLACEHOLDER ) {
                compiler_compile_sti( compiler, px );
            } else {
                compiler_emit( compiler, px, "\tc\n", GSTI );
                compiler_drop_top_expression( compiler );
                compiler_drop_top_expression( compiler );
            }
        }

	compiler_fixup_op_continue( compiler, px );
        compiler_fixup_here( compiler );
	compiler_compile_next( compiler, compiler_pop_offset( compiler, px ),
                               px );

	compiler_fixup_op_break( compiler, px );
	compiler_pop_loop( compiler );
	compiler_end_subscope( compiler, px );
      }

  | labeled_for '(' lvariable
      {
          char *loop_label =
              obtain_string_from_strpool( compiler->strpool, $1 );

          cexception_t inner;
          cexception_guard( inner ) {
              compiler_push_loop( compiler, loop_label,
                                  /* ncounters = */ 2, &inner );
              dnode_set_flags( compiler->loops, DF_LOOP_HAS_VAL );
          }
          cexception_catch {
              freex( loop_label );
              cexception_reraise( inner, px );
          }
          freex( loop_label );
        /* stack now: ..., lvariable_address */
      }
    in_loop_separator expression ')'
      {
        /* stack now:
           ..., lvariable_address, array_last_ptr */
        ssize_t neg_element_size = -1;
        ssize_t zero = 0;

        /* stack now: ..., lvariable_address, array_current_ptr */

        compiler_emit( compiler, px, "\tce\n", OFFSET, &neg_element_size );

        compiler_push_relative_fixup( compiler, px );
        compiler_emit( compiler, px, "\tce\n", JMP, &zero );

        /* The execution flow should return here after each iteration: */
        compiler_push_current_address( compiler, px );

        /* stack now: ..., lvariable_address, array_current_ptr */
        /* Store the current array element into the loop variable: */
        compiler_compile_over( compiler, px );
        compiler_compile_over( compiler, px );
        compiler_make_stack_top_element_type( compiler );
        compiler_make_stack_top_addressof( compiler, px );
        compiler_compile_ldi( compiler, px );
        compiler_compile_sti( compiler, px );
        compiler_end_subscope( compiler, px );
      }
     loop_body
      {
        /* stack now:
           ..., lvariable_address, array_current_ptr */
        ENODE *loop_var = compiler->e_stack; /* array_current_ptr */
        loop_var = loop_var ? enode_next( loop_var ) : NULL; /* lvariable_address */
        
        if( loop_var && !enode_has_flags( loop_var, EF_IS_READONLY )) {
            /* Store the current array element into the loop variable: */
            /* stack now:
               ..., lvariable_address, array_current_ptr */
            compiler_compile_over( compiler, px );
            compiler_compile_over( compiler, px );
            compiler_make_stack_top_element_type( compiler );
            compiler_make_stack_top_addressof( compiler, px );
            compiler_compile_swap( compiler, px );
            compiler_compile_ldi( compiler, px );
            compiler_compile_sti( compiler, px );
        }

	compiler_fixup_op_continue( compiler, px );
	compiler_fixup_here( compiler );
	compiler_compile_next( compiler, compiler_pop_offset( compiler, px ),
                               px );

	compiler_fixup_op_break( compiler, px );
	compiler_pop_loop( compiler );
      }

  | _TRY
      {
	cexception_t inner;
	ssize_t zero = 0;
	ssize_t try_var_offset = compiler->local_offset--;

	push_ssize_t( &compiler->try_variable_stack, &compiler->try_block_level,
		      try_var_offset, px );

	push_ssize_t( &compiler->catch_jumpover_stack,
		      &compiler->catch_jumpover_stack_length,
		      compiler->catch_jumpover_nr, px );

	compiler->catch_jumpover_nr = 0;

	cexception_guard( inner ) {
	    compiler_push_relative_fixup( compiler, &inner );
	    compiler_emit( compiler, px, "\tcee\n", TRY, &zero, &try_var_offset );
	}
	cexception_catch {
	    cexception_reraise( inner, px );
	}
      }
    compound_statement
      {
	ssize_t zero = 0;
	compiler_emit( compiler, px, "\tc\n", RESTORE );
	compiler_push_relative_fixup( compiler, px );
	compiler_emit( compiler, px, "\tce\n", JMP, &zero );
	compiler_swap_fixups( compiler );
	compiler_fixup_here( compiler );
      }
    opt_catch_list
      {
	int i;

	for( i = 0; i < compiler->catch_jumpover_nr; i ++ ) { 
	    compiler_fixup_here( compiler );
	}
	
	compiler->catch_jumpover_nr = 
	    pop_ssize_t( &compiler->catch_jumpover_stack, 
			 &compiler->catch_jumpover_stack_length, px );

	compiler_fixup_here( compiler );
	pop_ssize_t( &compiler->try_variable_stack,
		     &compiler->try_block_level, px );
      }

  ;

compound_statement
  : '{'
      {
	compiler_begin_subscope( compiler, px );
      }
    statement_list '}'
      {
	compiler_end_subscope( compiler, px );
      }
  ;

loop_body
  : _DO
      {
	compiler_begin_subscope( compiler, px );
      }
    statement_list
      {
	compiler_end_subscope( compiler, px );
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
        char *volatile catch_ident =
            obtain_string_from_strpool( compiler->strpool, $1 );
        char *opname = "exceptionval";
        ssize_t try_var_offset = compiler->try_variable_stack ?
            compiler->try_variable_stack[compiler->try_block_level-1] : 0;

        cexception_t inner;
        cexception_guard( inner ) {
            DNODE *catch_var = vartab_lookup( compiler->vartab, catch_ident );
            TNODE *catch_var_type = catch_var ? dnode_type( catch_var ) : NULL;

            if( !catch_var_type ||
                !compiler_lookup_operator( compiler, catch_var_type, opname, 1, &inner )) {
                yyerrorf( "type of variable in a 'catch' clause must "
                          "have unary '%s' operator", opname );
            } else {
                compiler_emit( compiler, &inner, "\n\tce\n", PLD, &try_var_offset );
                compiler_push_typed_expression( compiler,
                                                new_tnode_ref( &inner ),
                                                &inner );
                compiler_check_and_compile_operator( compiler, catch_var_type,
                                                     opname, /*arity:*/1,
                                                     /*fixup_values:*/ NULL,
                                                     &inner );
                compiler_emit( compiler, &inner, "\n" );
                compiler_compile_variable_assignment( compiler, catch_var, &inner );
            }
        }
        cexception_catch {
            freex( catch_ident );
            cexception_reraise( inner, px );
        }
        freex( catch_ident );
    }
  ;

catch_variable_declaration
  : _VAR identifier_list ':' var_type_description
    {
     char *opname = "exceptionval";
     DNODE *volatile var_list = $2;
     TNODE *volatile type_node = $4;
     TNODE *volatile shared_type_node = NULL;
     ssize_t try_var_offset = compiler->try_variable_stack ?
	 compiler->try_variable_stack[compiler->try_block_level-1] : 0;

     cexception_t inner;
     cexception_guard( inner ) {
         shared_type_node = share_tnode( type_node );
         dnode_list_append_type( var_list, shared_type_node );
         shared_type_node = NULL;
         dnode_list_assign_offsets( var_list, &compiler->local_offset );     
         if( var_list && dnode_list_length( var_list ) > 1 ) {
             yyerrorf( "only one variable may be declared in the 'catch' clause" );
         }
         if( !type_node || !compiler_lookup_operator( compiler, type_node,
                                                      opname, 1, &inner )) {
             yyerrorf( "type of variable declared in a 'catch' clause must "
                       "have unary '%s' operator", opname );
         } else {
             compiler_emit( compiler, &inner, "\n\tce\n", PLD, &try_var_offset );
             compiler_push_typed_expression( compiler, new_tnode_ref( &inner ), &inner );
             compiler_check_and_compile_operator( compiler, type_node, opname,
                                                  /*arity:*/1,
                                                  /*fixup_values:*/ NULL, &inner );
             compiler_emit( compiler, &inner, "\n" );
             compiler_compile_variable_assignment( compiler, var_list, &inner );
         }
         vartab_insert_named_vars( compiler->vartab, &var_list, &inner );
     }
     cexception_catch {
         delete_dnode( var_list );
         delete_tnode( type_node );
         delete_tnode( shared_type_node );
         cexception_reraise( inner, px );
     }
     assert( !var_list );
     delete_tnode( type_node );
     delete_tnode( shared_type_node );
    }
  | _VAR var_type_description uninitialised_var_declarator_list
    {
     DNODE *volatile var_list = $3;
     TNODE *volatile type_node = $2;
     TNODE *volatile shared_type_node = NULL;
     char *opname = "exceptionval";
     ssize_t try_var_offset = compiler->try_variable_stack ?
	 compiler->try_variable_stack[compiler->try_block_level-1] : 0;

     cexception_t inner;
     cexception_guard( inner ) {
         shared_type_node = share_tnode( type_node );
         dnode_list_append_type( var_list, shared_type_node );
         shared_type_node = NULL;
         dnode_list_assign_offsets( var_list, &compiler->local_offset );
         if( var_list && dnode_list_length( var_list ) > 1 ) {
             yyerrorf( "only one variable may be declared in "
                       "the 'catch' clause" );
         }
         if( !type_node ||
             !compiler_lookup_operator( compiler, type_node, opname, 1, &inner )) {
             yyerrorf( "type of variable declared in a 'catch' clause must "
                       "have unary '%s' operator", opname );
         } else {
             compiler_emit( compiler, &inner, "\n\tce\n", PLD, &try_var_offset );
             compiler_push_typed_expression( compiler, new_tnode_ref( &inner ), &inner );
             compiler_check_and_compile_operator( compiler, type_node, opname,
                                                  /*arity:*/1,
                                                  /*fixup_values:*/ NULL, &inner );
             compiler_emit( compiler, &inner, "\n" );
             compiler_compile_variable_assignment( compiler, var_list, &inner );
         }
         vartab_insert_named_vars( compiler->vartab, &var_list, &inner );
     }
     cexception_catch {
         delete_dnode( var_list );
         delete_tnode( type_node );
         delete_tnode( shared_type_node );
         cexception_reraise( inner, px );
     }
     assert( !var_list );
     delete_tnode( type_node );
     delete_tnode( shared_type_node );     
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
        char *volatile ident =
            obtain_string_from_strpool( compiler->strpool, $1 );
        cexception_t inner;
        cexception_guard( inner ) {
            compiler_emit_catch_comparison( compiler, NULL, ident, &inner );
        }
        cexception_catch {
            freex( ident );
            cexception_reraise( inner, px );
        }
        freex( ident );
        $$ = 0;
    }
  | module_list __COLON_COLON __IDENTIFIER
    {
        char *volatile ident =
            obtain_string_from_strpool( compiler->strpool, $3 );
        cexception_t inner;
        cexception_guard( inner ) {
            compiler_emit_catch_comparison( compiler, $1, ident, &inner );
        }
        cexception_catch {
            freex( ident );
            cexception_reraise( inner, px );
        }
        freex( ident );
        $$ = 0;
    }
  | exception_identifier_list ',' __IDENTIFIER
    {
        ssize_t zero = 0;
        char *volatile ident =
            obtain_string_from_strpool( compiler->strpool, $3 );
        cexception_t inner;
        cexception_guard( inner ) {
            compiler_push_relative_fixup( compiler, &inner );
            compiler_emit( compiler, &inner, "\tce\n", BJNZ, &zero );
            compiler_emit_catch_comparison( compiler, NULL, ident, &inner );
        }
        cexception_catch {
            freex( ident );
            cexception_reraise( inner, px );
        }
        freex( ident );
        $$ = $1 + 1;
    }
  | exception_identifier_list ',' module_list __COLON_COLON __IDENTIFIER
    {
      ssize_t zero = 0;
        char *volatile ident =
            obtain_string_from_strpool( compiler->strpool, $5 );
        cexception_t inner;
        cexception_guard( inner ) {
            compiler_push_relative_fixup( compiler, &inner );
            compiler_emit( compiler, &inner, "\tce\n", BJNZ, &zero );
            compiler_emit_catch_comparison( compiler, $3, ident, &inner );
        }
        cexception_catch {
            freex( ident );
            cexception_reraise( inner, px );
        }
        freex( ident );
        $$ = $1 + 1;
    }
  ;

catch_statement
  : _CATCH
    compound_statement
      {
	ssize_t zero = 0;
	compiler->catch_jumpover_nr ++;
	compiler_push_relative_fixup( compiler, px );
	compiler_emit( compiler, px, "\tce\n", JMP, &zero );
      }

  | _CATCH
      {
	compiler_begin_subscope( compiler,  px );
      }
    '(' catch_variable_list ')'
    compound_statement
      {
	ssize_t zero = 0;
	compiler->catch_jumpover_nr ++;
	compiler_push_relative_fixup( compiler, px );
	compiler_emit( compiler, px, "\tce\n", JMP, &zero );
	compiler_end_subscope( compiler, px );
      }

  | _CATCH exception_identifier_list
      {
	compiler_finish_catch_comparisons( compiler, $2, px );
	compiler_begin_subscope( compiler,  px );
      }
    '(' catch_variable_list ')'  
    compound_statement
      {
	compiler_end_subscope( compiler, px );
	compiler_finish_catch_block( compiler, px );
      }

  | _CATCH exception_identifier_list
      {
	compiler_finish_catch_comparisons( compiler, $2, px );
      }
    compound_statement
      {
	compiler_finish_catch_block( compiler, px );
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
    { $$ = new_tnode_array_snail( NULL, compiler->typetab, px ); }
  | type_identifier dimension_list
    {
        $$ = tnode_append_element_type( $2, $1 );
    }
  ;

undelimited_or_structure_description
  : struct_description
  | class_description
  | {
      cexception_t inner;
      TNODE * volatile tnode = NULL;

      cexception_guard( inner ) {
          tnode = new_tnode( &inner );
          tnode_set_flags( tnode, TF_IS_FORWARD );
          compiler_push_current_type( compiler, &tnode, &inner );
      }
      cexception_catch {
          delete_tnode( tnode );
          cexception_reraise( inner, px );
      }
    }
    struct_or_class_body
    {
        $$ = $2;
        delete_tnode( compiler_pop_current_type( compiler ));
    }
  | undelimited_type_description
  ;

type_identifier
  : __IDENTIFIER
     {
         char *ident = obtain_string_from_strpool( compiler->strpool, $1 );
	 $$ = compiler_lookup_tnode( compiler, NULL, ident, "type" );
         share_tnode( $$ );
         freex( ident );
     }
  | __IDENTIFIER _UNITS ':' __STRING_CONST
     {
         char *ident = obtain_string_from_strpool( compiler->strpool, $1 );
         char *units = obtain_string_from_strpool( compiler->strpool, $4 );

	 $$ = compiler_lookup_tnode( compiler, NULL, ident, "type" );
         share_tnode( $$ );

         freex( units );
         freex( ident );
     }
  | module_list __COLON_COLON __IDENTIFIER
     {
         char *ident = obtain_string_from_strpool( compiler->strpool, $3 );
	 $$ = compiler_lookup_tnode( compiler, $1, ident, "type" );
         share_tnode( $$ );
         freex( ident );
     }
  | module_list __COLON_COLON __IDENTIFIER _UNITS ':' __STRING_CONST
     {
         char *ident = obtain_string_from_strpool( compiler->strpool, $3 );
         char *units = obtain_string_from_strpool( compiler->strpool, $6 );

	 $$ = compiler_lookup_tnode( compiler, $1, ident, "type" );
         share_tnode( $$ );

         freex( units );
         freex( ident );
     }
  ;

opt_null_type_designator
  : _NOT _NULL
      { $$ = 1; }
  | _NULL
      { $$ = 0; }
  | '*' /* synonim of 'not null' */
      { $$ = 1; }
  | '?' /* synonim of 'null' */
      { $$ = 0; }
  | /* default: 1 == not null, 0 == null */
      { $$ = 1; }
  ; 

delimited_type_description
  : type_identifier
    { 
       $$ = $1;
    }

  | _LIKE var_type_description
    {
        TNODE *shared_var_type = share_tnode( $2 );
	assert( compiler->current_type );
        assert( $2 );
        tnode_insert_base_type( compiler->current_type, &shared_var_type );
        tnode_insert_element_type( compiler->current_type,
                                   share_tnode( tnode_element_type( $2 )));
        if( tnode_is_reference( $2 )) {
            tnode_set_flags( compiler->current_type, TF_IS_REF );
        }
        tnode_set_flags( compiler->current_type, TF_IS_EQUIVALENT );
        tnode_set_kind( compiler->current_type, TK_DERIVED );
    }
    struct_or_class_body
    {
	/* $$ = new_tnode_derived( share_tnode( $2 ), px ); */
	$$ = new_tnode_equivalent( $2, px );

	assert( compiler->current_type );
        assert( $4 );

        if( tnode_suffix( $4 )) {
            tnode_set_suffix( $$, tnode_suffix( $4 ), px );
        } else {
            tnode_set_suffix( $$, tnode_name( compiler->current_type ), px );
        }

	$$ = tnode_move_operators( $$, $4 );

	dispose_tnode( &$4 );
	dispose_tnode( &$2 );
   }

  | type_identifier _OF delimited_type_description
    {
      TNODE *composite = $1;
      $$ = new_tnode_derived( composite, px );
      tnode_set_kind( $$, TK_COMPOSITE );
      tnode_insert_element_type( $$, $3 );
    }
  | _ADDRESSOF
    { $$ = new_tnode_addressof( NULL, px ); }

  | _ARRAY _OF delimited_type_description
    { $$ = new_tnode_array_snail( $3, compiler->typetab, px ); }

  | _ARRAY dimension_list _OF delimited_type_description
    { $$ = tnode_append_element_type( $2, $4 ); }

  | _TYPE __IDENTIFIER
    {
	char *volatile type_name =
            obtain_string_from_strpool( compiler->strpool, $2 );
	TNODE *volatile tnode =
            share_tnode( typetab_lookup( compiler->typetab, type_name ));
	TNODE *volatile shared_tnode = NULL;

        cexception_t inner;
        cexception_guard( inner ) {
            if( !tnode ) {
                tnode = new_tnode_placeholder( type_name, &inner );
                shared_tnode = share_tnode( tnode );
                typetab_insert( compiler->typetab, type_name,
                                &shared_tnode, &inner );
                assert( !shared_tnode );
            }
        }
        cexception_catch {
            freex( type_name );
            delete_tnode( tnode );
            delete_tnode( shared_tnode );
            cexception_reraise( inner, px );
        }
        freex( type_name );
	$$ = tnode;
    }

  | function_or_procedure_type_keyword '(' argument_list ')'
    {
	int is_function = $1;
	TNODE *base_type = typetab_lookup( compiler->typetab, "procedure" );

	share_tnode( base_type );
	$$ = new_tnode_function_or_proc_ref( $3, NULL, base_type, px );
	if( is_function ) {
	    compiler_set_function_arguments_readonly( $$ );
	}
    }
  | function_or_procedure_type_keyword '(' argument_list ')'
    __ARROW '(' retval_description_list ')'
    {
	int is_function = $1;
	TNODE *base_type = typetab_lookup( compiler->typetab, "procedure" );

	share_tnode( base_type );
	$$ = new_tnode_function_or_proc_ref( $3, $7, base_type, px );
	if( is_function ) {
	    compiler_set_function_arguments_readonly( $$ );
	}
    }

  | _BLOB
    { $$ = new_tnode_blob_snail( compiler->typetab, px ); }
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

opt_implemented_interfaces
  : _IMPLEMENTS interface_identifier_list
  { $$ = $2; }
  | /* empty */
  { $$ = NULL; }
  ;

interface_identifier_list
  : type_identifier
  {
      TLIST *interfaces = NULL;
      if( $1 ) {
          tlist_push_tnode( &interfaces, &$1, px );
      }
      $$ = interfaces;
  }
  |  type_identifier ',' interface_identifier_list
  {
      if( $1 ) {
          tlist_push_tnode( &$3, &$1, px );
      }
      $$ = $3;
  }
  ;

struct_description
  : opt_null_type_designator _STRUCT
    {
        cexception_t inner;
        TNODE * volatile tnode = NULL;

        cexception_guard( inner ) {
            tnode = new_tnode_forward_struct( /* name = */ NULL, &inner );
            if( $1 ) {
                tnode_set_flags( tnode, TF_NON_NULL );
            }
            compiler_push_current_type( compiler, &tnode, &inner );
        }
        cexception_catch {
            delete_tnode( tnode );
            cexception_reraise( inner, px );
        }
    }
    struct_or_class_body
    {
        $$ = tnode_finish_struct( $4, px );
        if( $1 ) {
            tnode_set_flags( $$, TF_NON_NULL );
        }
        delete_tnode( compiler_pop_current_type( compiler ));
    }
;

class_description
  : opt_null_type_designator _CLASS 
    {
        cexception_t inner;
        TNODE * volatile tnode = NULL;

        compiler_begin_subscope( compiler, px );
        cexception_guard( inner ) {
            tnode = new_tnode_forward_class( /* name = */ NULL, &inner );
            if( $1 ) {
                tnode_set_flags( tnode, TF_NON_NULL );
            }
            compiler_push_current_type( compiler, &tnode, &inner );
        }
        cexception_catch {
            delete_tnode( tnode );
            cexception_reraise( inner, px );
        }
    }
    struct_or_class_body
    {
        compiler_finish_virtual_method_table( compiler, $4, px );
        $$ = tnode_finish_class( $4, px );
        if( $1 ) {
            tnode_set_flags( $$, TF_NON_NULL );
        }
        delete_tnode( compiler_pop_current_type( compiler ));
        compiler_end_subscope( compiler, px );
    }
;

undelimited_type_description
  : _ARRAY _OF undelimited_or_structure_description
    { $$ = new_tnode_array_snail( $3, compiler->typetab, px ); }

  | _ARRAY dimension_list _OF undelimited_or_structure_description
    { $$ = tnode_append_element_type( $2, $4 ); }

  | type_identifier _OF undelimited_or_structure_description
    {
      TNODE *composite = $1;
      $$ = new_tnode_derived( composite, px );
      tnode_insert_element_type( $$, $3 );
    }

  | '(' var_type_description ')'
    { $$ = $2; }

  | _ENUM __IDENTIFIER '(' enum_member_list ')'
    {
        char *volatile enum_name =
            obtain_string_from_strpool( compiler->strpool, $2 );

        TNODE *enum_implementing_type = typetab_lookup( compiler->typetab, enum_name );
        ssize_t tsize = enum_implementing_type ?
            tnode_size( enum_implementing_type ) : 0;

        if( compiler->current_type &&
            tnode_is_forward( compiler->current_type )) {
            tnode_set_kind( compiler->current_type, TK_ENUM );
            tnode_set_size( compiler->current_type, tsize );
        }
        cexception_t inner;
        cexception_guard( inner ) {
            $$ = tnode_finish_enum( $4, NULL, enum_implementing_type, &inner );
        }
        cexception_catch {
            freex( enum_name );
            cexception_reraise( inner, px );
        }
        freex( enum_name );
        compiler_check_enum_attributes( $$ );
    }

  | '(' __THREE_DOTS ',' enum_member_list ')'
    {
      if( !compiler->current_type ||
	  tnode_is_forward( compiler->current_type )) {
	  yyerror( "one can only extend previously defined enumeration types" );
      }
      $$ = $4;
    }
  ;

enum_member_list
  : enum_member
     {
       $$ = new_tnode( px );
       tnode_set_kind( $$, TK_ENUM );
       if( compiler->current_type ) {
	   tnode_merge_field_lists( $$, compiler->current_type );
       }
       tnode_insert_enum_value( $$, $1 );
     }

  | enum_member_list ',' enum_member
     { $$ = tnode_insert_enum_value( $1, $3 ); }
;

enum_member
  : __IDENTIFIER
    {
        char *member_name =
            obtain_string_from_strpool( compiler->strpool, $1 );
	$$ = new_dnode_name( member_name, px );
        freex( member_name );
    }
  | __IDENTIFIER '=' constant_integer_expression
    {
        char *member_name =
            obtain_string_from_strpool( compiler->strpool, $1 );
	$$ = new_dnode_name( member_name, px );
	dnode_set_offset( $$, $3 );
        freex( member_name );
    }
  | __THREE_DOTS
    {
	$$ = new_dnode_name( "...", px );
    }
  | /* empty */
    { $$ = NULL; }
  ;


inheritance_and_implementation_list
  : opt_base_type opt_implemented_interfaces
  {
      TNODE *current_class = compiler->current_type;
      TNODE *base_type = $1 ?
          $1 : share_tnode(typetab_lookup( compiler->typetab, "struct" ));
      TNODE *shared_base_type = share_tnode( base_type );
      TLIST *interfaces = $2;

      if( base_type && current_class != base_type ) {
          if( !tnode_base_type( current_class )) {
              tnode_insert_base_type( current_class, &shared_base_type );
          }
      }

      if( !tnode_interface_list( current_class )) {
          tnode_insert_interfaces( current_class, interfaces );
      }
      compiler_start_virtual_method_table( compiler, current_class, px );

      delete_tnode( shared_base_type );
      $$ = base_type;
  }
;

struct_or_class_body
  : inheritance_and_implementation_list
    '{' struct_field_list '}'
    { $$ = $3; }
  | inheritance_and_implementation_list
    '{' struct_field_list struct_operator_list opt_semicolon '}'
    { $$ = $3; }
  ;

struct_field_list
  : struct_field
     {
	 assert( compiler->current_type );
	 $$ = share_tnode( compiler->current_type );
         tnode_insert_type_member( $$, $1 );
     }
  | type_attribute
     {
       cexception_t inner;

       cexception_guard( inner ) {
	   assert( compiler->current_type );
	   $$ = share_tnode( compiler->current_type );
	   tnode_set_attribute( $$, $1, &inner );
       }
       cexception_catch {
	   delete_anode( $1 );
	   cexception_reraise( inner, px );
       }
       delete_anode( $1 );
     }
  | struct_field_list ';' struct_field
     {
         $$ = tnode_insert_type_member( $1, $3 );
     }
  | struct_field_list ';' type_attribute
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
	TNODE *struct_type = compiler->current_type;
        assert( struct_type );
	tnode_insert_type_member( struct_type, $1 );
	$$ = struct_type;
    }
  | struct_operator_list struct_operator
    {
	TNODE *struct_type = compiler->current_type;
        assert( struct_type );
	tnode_insert_type_member( struct_type, $2 );
	$$ = $1;
    }
  | struct_operator_list ';' struct_operator
    {
	TNODE *struct_type = compiler->current_type;
        assert( struct_type );
	tnode_insert_type_member( struct_type, $3 );
	$$ = $1;
    }
;

struct_operator
  : operator_definition
  | method_definition
  | method_header
  | constructor_definition
  | constructor_header
  | destructor_header
  | destructor_definition
  ;

interface_type_placeholder
  : /* empty */
     {
         assert( compiler->current_type );
	 $$ = share_tnode( compiler->current_type );
     }
  ;

interface_declaration_body
  : inheritance_and_implementation_list '{'
    interface_type_placeholder
    interface_operator_list opt_semicolon '}'
    {
        assert( compiler->current_type );
        TNODE *current_type = compiler->current_type;
        TLIST *implemented_interfaces = tnode_interface_list( current_type );
        TNODE *base_type = $1;
        TNODE *struct_type = typetab_lookup( compiler->typetab, "struct" );
        if( implemented_interfaces != NULL ) {
            yyerrorf( "interface ('%s') can not implement other interfaces",
                      current_type ? tnode_name( current_type ) : "?" );
        }
        if( base_type && tnode_kind( base_type ) != TK_INTERFACE &&
            base_type != struct_type ) {
            yyerrorf( "interfaces ('%s') can only inherit from other interfaces",
                      current_type ? tnode_name( current_type ) : "?");
        }
        $$ = current_type;
    }
  ;

interface_operator_list
  : interface_operator
    {
	TNODE *struct_type = compiler->current_type;
	tnode_insert_type_member( struct_type, $1 );
	$$ = struct_type;
    }
  | interface_operator_list interface_operator
    {
	tnode_insert_type_member( $1, $2 );
	$$ = $1;
    }
  | interface_operator_list ';' interface_operator
    {
	tnode_insert_type_member( $1, $3 );
	$$ = $1;
    }
;

interface_operator
  : method_header
  | method_definition
  ;

struct_var_declaration
  : identifier_list ':' var_type_description
      {
       $$ = dnode_list_append_type( $1, $3 );
      }

  | _VAR identifier_list ':' var_type_description
      {
       $$ = dnode_list_append_type( $2, $4 );
      }

  | _VAR var_type_description uninitialised_var_declarator_list
      {
        $$ = dnode_list_append_type( $3, $2 );
      }

  | var_type_description uninitialised_var_declarator_list
      {
        $$ = dnode_list_append_type( $2, $1 );
      }

  ;

size_constant
  : _SIZEOF type_identifier
    {
      TNODE *tnode = $2;

      if( tnode ) {
	  $$ = tnode_size( tnode );
          delete_tnode( tnode );
      }
    }
  | _SIZEOF _NATIVE __STRING_CONST
    {
        char *size_str = obtain_string_from_strpool( compiler->strpool, $3 );
        $$ = compiler_native_type_size( size_str );
        freex( size_str );
    }
  | _NATIVE __STRING_CONST /* _REF */ '*'
    {
        char *size_str = obtain_string_from_strpool( compiler->strpool, $2 );
        $$ = compiler_native_type_nreferences( size_str );
        freex( size_str );
    }
  ;

type_attribute
  : __IDENTIFIER
    {
        char *attribute = obtain_string_from_strpool( compiler->strpool, $1 );
        $$ = new_anode_integer_attribute( attribute, 1, px );
        freex( attribute );
    }
  | __IDENTIFIER '=' __INTEGER_CONST
    {
        char *attribute = obtain_string_from_strpool( compiler->strpool, $1 );
        char *value = obtain_string_from_strpool( compiler->strpool, $3 );
        $$ = new_anode_integer_attribute( attribute, atol( value ), px );
        freex( attribute );
        freex( value );
    }
  | __IDENTIFIER '=' size_constant
    {
        char *attribute = obtain_string_from_strpool( compiler->strpool, $1 );
        $$ = new_anode_integer_attribute( attribute, $3, px );
        freex( attribute );
    }
  | __IDENTIFIER '=' __IDENTIFIER
    {
        char *attribute = obtain_string_from_strpool( compiler->strpool, $1 );
        char *value = obtain_string_from_strpool( compiler->strpool, $3 );
        $$ = new_anode_string_attribute( attribute, value, px );
        freex( attribute );
        freex( value );
    }
  | __IDENTIFIER '=' __STRING_CONST
    {
        char *attribute = obtain_string_from_strpool( compiler->strpool, $1 );
        char *value = obtain_string_from_strpool( compiler->strpool, $3 );
        $$ = new_anode_string_attribute( attribute, value, px );
        freex( attribute );
        freex( value );
    }
  ;

dimension_list
  : '[' ']'
    { $$ = new_tnode_array_snail( NULL, compiler->typetab, px ); }
  | dimension_list '[' ']'
    {
      TNODE *array_type = new_tnode_array_snail( NULL, compiler->typetab, px );
      $$ = tnode_append_element_type( $1, array_type );
    }
  ;

/*--------------------------------------------------------------------------*/

/* type_declaration */

type_declaration_name
  : __IDENTIFIER
    { $$ = $1; }

  | _STRUCT
    { $$ = strpool_add_string( compiler->strpool, "struct", px); }

  | _ARRAY
    { $$ = strpool_add_string( compiler->strpool, "array", px ); }

  | _PROCEDURE
    { $$ = strpool_add_string( compiler->strpool, "procedure", px ); }

  | _BLOB
    { $$ = strpool_add_string( compiler->strpool, "blob", px ); }
;

type_declaration_start
  : _TYPE type_declaration_name
      {
        char *type_name = obtain_string_from_strpool( compiler->strpool, $2 );
	TNODE *old_tnode = typetab_lookup_silently( compiler->typetab, type_name );
	TNODE *volatile shared_tnode = NULL;

	if( !old_tnode || !tnode_is_extendable_enum( old_tnode )) {
            compiler_insert_new_type( compiler, type_name, /*not_null =*/0,
                                      new_tnode_forward, px );
	}
	shared_tnode = 
            share_tnode( typetab_lookup_silently( compiler->typetab,
                                                  type_name ));
	assert( !compiler->current_type );
	compiler_push_current_type( compiler, &shared_tnode, px );
	compiler_begin_scope( compiler, px );
        freex( type_name );
      }
;

delimited_type_declaration
  : type_declaration_start '=' delimited_type_description
      {
	compiler_end_scope( compiler, px );
	compiler_compile_type_declaration( compiler, $3, px );
      }
  | type_declaration_start '=' _NEW var_type_description
      {
        cexception_t inner;
        TNODE * type_description = $4;
        TNODE * volatile ntype = NULL; /* new type */
	compiler_end_scope( compiler, px );
        cexception_guard( inner ) {
            ntype = new_tnode_derived( type_description, &inner );
            assert( compiler->current_type );
            tnode_set_name( ntype, tnode_name( compiler->current_type ),
                            &inner );
            tnode_copy_operators( ntype, $4, &inner );
            compiler_compile_type_declaration( compiler, ntype, &inner );
            ;        }
        cexception_catch {
            delete_tnode( ntype );
            cexception_reraise( inner, px );
        }
      }

  | type_declaration_start '=' _NEW var_type_description struct_or_class_body
      {
        cexception_t inner;
        TNODE * type_description = $4;
        TNODE * volatile ntype = NULL; /* new type */
	compiler_end_scope( compiler, px );
        cexception_guard( inner ) {
            ntype = new_tnode_derived( type_description, &inner );
            assert( compiler->current_type );
            tnode_set_name( ntype, tnode_name( compiler->current_type ),
                            &inner );

            tnode_copy_operators( ntype, $4, &inner );
            tnode_move_operators( ntype, $5 );

            if( tnode_suffix( $5 )) {
                tnode_set_suffix( ntype, tnode_suffix( $5 ), px );
            } else {
                tnode_set_suffix( ntype, tnode_name( compiler->current_type ), px );
            }

            delete_tnode( $5 );
            $5 = NULL;
            compiler_compile_type_declaration( compiler, ntype, &inner );
        }
        cexception_catch {
            delete_tnode( ntype );
            cexception_reraise( inner, px );
        }
      }

  | type_declaration_start '=' delimited_type_description initialiser
      {
        compiler_compile_drop( compiler, px );
	compiler_end_scope( compiler, px );
	compiler_compile_type_declaration( compiler, $3, px );
      }
  | type_declaration_start
      {
	compiler_end_scope( compiler, px );
	delete_tnode( compiler_pop_current_type( compiler ));
      }
  | forward_struct_declaration
  | forward_class_declaration
  ;

undelimited_type_declaration
  : type_declaration_start '=' undelimited_type_description
      {
	compiler_end_scope( compiler, px );
	compiler_compile_type_declaration( compiler, $3, px );
	compiler->current_type = NULL;
      }

  | type_declaration_start '=' undelimited_type_description type_initialiser
      {
	compiler_end_scope( compiler, px );
	compiler_compile_type_declaration( compiler, $3, px );
	compiler->current_type = NULL;
      }

  | struct_declaration
  | class_declaration
  | interface_declaration
  ;

type_of_type_declaration
  : _TYPE __IDENTIFIER _OF __IDENTIFIER '='
      {
        char *volatile type_name =
            obtain_string_from_strpool( compiler->strpool, $2 );
        char *volatile element_name =
            obtain_string_from_strpool( compiler->strpool, $4 );
	TNODE * volatile base = NULL;
	TNODE * volatile shared_base = NULL;
	TNODE * volatile tnode = NULL;
	TNODE * volatile shared_tnode = NULL;
	cexception_t inner;

	cexception_guard( inner ) {
	    base = new_tnode_placeholder( element_name, &inner );
            shared_base = share_tnode( base );

	    tnode = new_tnode_composite( type_name, base, &inner );
            base = NULL;

	    tnode_set_flags( tnode, TF_IS_FORWARD );
	    compiler_typetab_insert( compiler, &tnode, &inner );

	    shared_tnode =
                share_tnode( typetab_lookup( compiler->typetab, type_name ));
	    compiler_push_current_type( compiler, &shared_tnode, &inner );

	    compiler_typetab_insert( compiler, &shared_base, &inner );
	    compiler_begin_scope( compiler, &inner );
	}
	cexception_catch {
	    delete_tnode( base );
	    delete_tnode( shared_base );
	    delete_tnode( tnode );
	    delete_tnode( shared_tnode );
            freex( type_name );
            freex( element_name );
	    cexception_reraise( inner, px );
	}
        freex( type_name );
        freex( element_name );
      }
    undelimited_type_description
      {
	compiler_end_scope( compiler, px );
	compiler_compile_type_declaration( compiler, $7, px );
	delete_tnode( compiler_pop_current_type( compiler ));
      }

  |  _TYPE __IDENTIFIER _OF __IDENTIFIER '=' opt_null_type_designator _STRUCT
      {
        char *volatile type_name =
            obtain_string_from_strpool( compiler->strpool, $2 );
        char *volatile element_name =
            obtain_string_from_strpool( compiler->strpool, $4 );
	TNODE * volatile base = NULL;
	TNODE * volatile shared_base = NULL;
	TNODE * volatile tnode = NULL;
	TNODE * volatile shared_tnode = NULL;

	cexception_t inner;
	cexception_guard( inner ) {
	    base = new_tnode_placeholder( element_name, &inner );
            shared_base = share_tnode( base );

	    tnode = new_tnode_composite( type_name, base, &inner );
            base = NULL;

	    tnode_set_flags( tnode, TF_IS_FORWARD );
	    compiler_typetab_insert( compiler, &tnode, &inner );

	    shared_tnode =
                share_tnode( typetab_lookup( compiler->typetab, type_name ));
	    compiler_push_current_type( compiler, &shared_tnode, &inner );

	    compiler_typetab_insert( compiler, &shared_base, &inner );
	    compiler_begin_scope( compiler, &inner );
	}
	cexception_catch {
	    delete_tnode( base );
	    delete_tnode( shared_base );
	    delete_tnode( tnode );
	    delete_tnode( shared_tnode );
            freex( type_name );
            freex( element_name );
	    cexception_reraise( inner, px );
	}
        freex( type_name );
        freex( element_name );
      }
      struct_or_class_body
      {
        if( $6 ) {
            tnode_set_flags( $9, TF_NON_NULL );
        }
	compiler_end_scope( compiler, px );
	compiler_compile_type_declaration( compiler, $9, px );
	delete_tnode( compiler_pop_current_type( compiler ));
      }

  | _TYPE __IDENTIFIER _OF __IDENTIFIER '=' opt_null_type_designator
      {
        char *volatile type_name =
            obtain_string_from_strpool( compiler->strpool, $2 );
        char *volatile element_name =
            obtain_string_from_strpool( compiler->strpool, $4 );
	TNODE * volatile base = NULL;
	TNODE * volatile shared_base = NULL;
	TNODE * volatile tnode = NULL;
	cexception_t inner;

	cexception_guard( inner ) {
	    base = new_tnode_placeholder( element_name, &inner );
            shared_base = share_tnode( base );
	    tnode = new_tnode_composite( type_name, base, &inner );
            base = NULL;

	    tnode_set_flags( tnode, TF_IS_FORWARD );
	    compiler_typetab_insert( compiler, &tnode, &inner );

	    tnode =
                share_tnode( typetab_lookup( compiler->typetab, type_name ));

	    compiler->current_type = moveptr( (void**)&tnode );
	    compiler_typetab_insert( compiler, &shared_base, &inner );
	    compiler_begin_scope( compiler, &inner );
	}
	cexception_catch {
	    delete_tnode( base );
	    delete_tnode( tnode );
            freex( type_name );
            freex( element_name );
	    cexception_reraise( inner, px );
	}
        assert( !tnode );
        assert( !base );
        assert( !shared_base );
        freex( type_name );
        freex( element_name );
      }
    struct_or_class_body
      {
        if( $6 ) {
            tnode_set_flags( $8, TF_NON_NULL );
        }
	compiler_end_scope( compiler, px );
	compiler_compile_type_declaration( compiler, $8, px );
	compiler->current_type = NULL;
      }
;

struct_declaration
  : opt_null_type_designator _STRUCT __IDENTIFIER
    {
        char *struct_name =
            obtain_string_from_strpool( compiler->strpool, $3 );
	TNODE *old_tnode = typetab_lookup( compiler->typetab, struct_name );
	TNODE *tnode = NULL;

	if( !old_tnode ) {
            compiler_insert_new_type( compiler, struct_name, /*not_null =*/$1,
                                      new_tnode_forward_struct, px );
	} else {
            if( tnode_is_non_null_reference( old_tnode ) !=
                ($1 ? 1 : 0 )) {
                yyerrorf( "definition of forward structure '%s' "
                          "has different non-null flag", struct_name );
            }
        }
	tnode = typetab_lookup( compiler->typetab, struct_name );
	assert( !compiler->current_type );
        share_tnode( tnode );
	compiler->current_type = moveptr( (void**)&tnode );
	compiler_begin_scope( compiler, px );
        freex( struct_name );
    }
    struct_or_class_body
    {
	tnode_finish_struct( $5, px );
	compiler_end_scope( compiler, px );
	compiler_typetab_insert( compiler, &$5, px );
        compiler->current_type = NULL;
    }
  | type_declaration_start '=' opt_null_type_designator _STRUCT
    {
	assert( compiler->current_type );
	tnode_set_flags( compiler->current_type, TF_IS_REF );
        tnode_set_kind( compiler->current_type, TK_STRUCT );
    }
    struct_or_class_body
    {
        if( $3 ) {
            tnode_set_flags( $6, TF_NON_NULL );
        }
	tnode_finish_struct( $6, px );
	compiler_end_scope( compiler, px );
	compiler_compile_type_declaration( compiler, $6, px );
        compiler->current_type = NULL;
    }
  | type_declaration_start '=' opt_null_type_designator
    {
	assert( compiler->current_type );
    }
    struct_or_class_body
    {
        if( $3 ) {
            tnode_set_flags( $5, TF_NON_NULL );
        }
	compiler_end_scope( compiler, px );
	compiler_compile_type_declaration( compiler, $5, px );
        compiler->current_type = NULL;
    }

  | type_of_type_declaration
;

class_declaration
  : opt_null_type_designator _CLASS __IDENTIFIER
    {
        char *struct_name =
            obtain_string_from_strpool( compiler->strpool, $3 );
	TNODE *old_tnode = typetab_lookup( compiler->typetab, struct_name );
	TNODE *tnode = NULL;

	if( !old_tnode ) {
            compiler_insert_new_type( compiler, struct_name, /*not_null=*/$1,
                                      new_tnode_forward_class, px );
	}
	tnode = typetab_lookup( compiler->typetab, struct_name );
	assert( !compiler->current_type );
	compiler->current_type = share_tnode( tnode );
	compiler_begin_scope( compiler, px );
        freex( struct_name );
    }
    struct_or_class_body
    {
 	tnode_finish_class( $5, px );
	compiler_finish_virtual_method_table( compiler, $5, px );
	compiler_end_scope( compiler, px );
	compiler_typetab_insert( compiler, &$5, px );
	compiler->current_type = NULL;
    }
  | type_declaration_start '=' opt_null_type_designator _CLASS
    {
	assert( compiler->current_type );
	tnode_set_flags( compiler->current_type, TF_IS_REF );
        tnode_set_kind( compiler->current_type, TK_CLASS );
    }
    struct_or_class_body
    {
        if( $3 ) {
            tnode_set_flags( $6, TF_NON_NULL );
        }
 	tnode_finish_class( $6, px );
	compiler_finish_virtual_method_table( compiler, $6, px );
	compiler_end_scope( compiler, px );
	compiler_compile_type_declaration( compiler, $6, px );
	compiler->current_type = NULL;
    }
;

interface_declaration
  : opt_null_type_designator _INTERFACE __IDENTIFIER
    {
        char *struct_name =
            obtain_string_from_strpool( compiler->strpool, $3 );
	TNODE *old_tnode = typetab_lookup( compiler->typetab, struct_name );
	TNODE *tnode = NULL;

	if( !old_tnode ) {
            compiler_insert_new_type( compiler, struct_name, /*not_null=*/$1,
                                      new_tnode_forward_interface, px );
	}
	tnode = typetab_lookup( compiler->typetab, struct_name );
	assert( !compiler->current_type );
	compiler->current_type = share_tnode( tnode );
	compiler_begin_scope( compiler, px );
        freex( struct_name );
    }
    interface_declaration_body
    {
 	tnode_finish_interface( $5, ++compiler->last_interface_number, px );
	compiler_end_scope( compiler, px );
	compiler_typetab_insert( compiler, &$5, px );
	compiler->current_type = NULL;
    }
;

forward_struct_declaration
  : opt_null_type_designator _STRUCT __IDENTIFIER
      {
          char *struct_name =
              obtain_string_from_strpool( compiler->strpool, $3 );

          compiler_insert_new_type( compiler, struct_name, /*not_null=*/$1,
                                    new_tnode_forward_struct, px );

          freex( struct_name );
      }
;

forward_class_declaration
  : opt_null_type_designator _CLASS __IDENTIFIER
      {
          char *struct_name =
              obtain_string_from_strpool( compiler->strpool, $3 );

          compiler_insert_new_type( compiler, struct_name, /*not_null=*/$1,
                                    new_tnode_forward_class, px );

          freex( struct_name );
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
  a[i], b, c = b + c, d, f( x, y );
  a, b   = f( x, y, z );

*/

lvalue_list
: lvalue
      {
	  compiler_push_thrcode( compiler, px );
	  $$ = 1;
      }
| __IDENTIFIER
      {
          char *ident = obtain_string_from_strpool( compiler->strpool, $1 );
	  compiler_push_varaddr_expr( compiler, ident, px );
	  compiler_push_thrcode( compiler, px );
          freex( ident );
	  $$ = 1;
      }
| lvalue_list ',' lvalue
      {
	  compiler_push_thrcode( compiler, px );
	  $$ = $1 + 1;
      }
| lvalue_list ',' __IDENTIFIER
      {
          char *ident = obtain_string_from_strpool( compiler->strpool, $3 );
	  compiler_push_varaddr_expr( compiler, ident, px );
	  compiler_push_thrcode( compiler, px );
          freex( ident );
	  $$ = $1 + 1;
      }
;

assignment_statement
  : variable_access_identifier '=' expression
      {
	  compiler_compile_store_variable( compiler, $1, px );
      }
  | lvalue '=' expression
      {
	  compiler_compile_sti( compiler, px );
      }

  | lvalue ',' 
      {
	  compiler_push_thrcode( compiler, px );
      }
    lvalue_list '=' multivalue_expression_list
      {
	  compiler_compile_multiple_assignment( compiler, $4+1, $4, $6, px );
	  compiler_compile_sti( compiler, px );
      }

  | __IDENTIFIER ',' 
      {
          char *ident = obtain_string_from_strpool( compiler->strpool, $1 );
	  compiler_push_varaddr_expr( compiler, ident, px );
	  compiler_push_thrcode( compiler, px );
          freex( ident );
      }
    lvalue_list '=' multivalue_expression_list
      {
	  compiler_compile_multiple_assignment( compiler, $4+1, $4, $6, px );

	  {
	      DNODE *var;

	      compiler_swap_top_expressions( compiler );
	      var = enode_variable( compiler->e_stack );

	      share_dnode( var );
	      compiler_drop_top_expression( compiler );
	      compiler_compile_variable_assignment( compiler, var, px );
	      delete_dnode( var );
	  }
      }

  | variable_access_identifier
      {
	  compiler_compile_load_variable_value( compiler, $1, px );
      }
    __ARITHM_ASSIGN expression
      {
          char *opname = obtain_string_from_strpool( compiler->strpool, $3 );
          compiler_compile_binop( compiler, opname, px );
          compiler_compile_store_variable( compiler, $1, px );
          freex( opname );
      }
  | lvalue
      {
	  compiler_compile_dup( compiler, px );
	  compiler_compile_ldi( compiler, px );
      }
    __ARITHM_ASSIGN expression
      { 
          char *opname = obtain_string_from_strpool( compiler->strpool, $3 );
	  compiler_compile_binop( compiler, opname, px );
	  compiler_compile_sti( compiler, px );
          freex( opname );
      }

  | lvalue
      {
	  compiler_compile_ldi( compiler, px );
      }
     __ASSIGN expression
      {
	  int err = 0;
	  if( !compiler_test_top_types_are_assignment_compatible(
	           compiler, px )) {
	      yyerrorf( "incopatible types for value-copy assignment ':='" );
	  }
	  compiler_emit( compiler, px, "\tc\n", COPY );
	  if( !err && !compiler_stack_top_is_reference( compiler )) {
	      yyerrorf( "value assignemnt := works only for references" );
	      err = 1;
	  }
	  if( !err &&
	      !compiler_test_top_types_are_readonly_compatible_for_copy(
	           compiler, px )) {
	      yyerrorf( "can not copy into the readonly value "
                        "in the value-copy assignment ':='" );
	      err = 1;
	  }
	  compiler_drop_top_expression( compiler );
	  if( !err && !compiler_stack_top_is_reference( compiler )) {
	      yyerrorf( "value assignemnt := works only for references" );
	      err = 1;
	  }
	  compiler_drop_top_expression( compiler );
      }

  | variable_access_identifier
      {
	  compiler_compile_load_variable_value( compiler, $1, px );
      }
    __ASSIGN expression
      {
	  int err = 0;
	  if( !compiler_test_top_types_are_assignment_compatible(
	           compiler, px )) {
	      yyerrorf( "incopatible types for value-copy assignment ':='" );
	      err = 1;
	  }
	  compiler_emit( compiler, px, "\tc\n", COPY );
	  if( !err && !compiler_stack_top_is_reference( compiler )) {
	      yyerrorf( "value assignemnt := works only for references" );
	      err = 1;
	  }
	  if( !err &&
	      !compiler_test_top_types_are_readonly_compatible_for_copy(
	           compiler, px )) {
	      yyerrorf( "can not copy into the readonly value in "
                        "the value-copy assignment ':='" );
	      err = 1;
	  }
	  compiler_drop_top_expression( compiler );
	  if( !err && !compiler_stack_top_is_reference( compiler )) {
	      yyerrorf( "value assignemnt := works only for references" );
	      err = 1;
	  }
	  compiler_drop_top_expression( compiler );
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
      {
          char *opcode = obtain_string_from_strpool( compiler->strpool, $1 );
          compiler_emit( compiler, px, "\tC\n", opcode );
          freex( opcode );
      }
  | module_list __COLON_COLON __IDENTIFIER
      {
          char *opcode = obtain_string_from_strpool( compiler->strpool, $3 );
          compiler_emit( compiler, px, "\tMC\n", 
                         $1 ? dnode_name($1) : "???", opcode );
          freex( opcode );
      }
  | __IDENTIFIER ':' __IDENTIFIER
      {
          char *libname = obtain_string_from_strpool( compiler->strpool, $1 );
          char *opcode = obtain_string_from_strpool( compiler->strpool, $3 );
          compiler_emit( compiler, px, "\tMC\n", libname, opcode );
          freex( libname );
          freex( opcode );
      }
  ;

variable_reference
  : '%' __IDENTIFIER
      {
          char *ident = obtain_string_from_strpool( compiler->strpool, $2 );
          DNODE *varnode = vartab_lookup( compiler->vartab, ident );
          if( varnode ) {
              ssize_t var_offset = dnode_offset( varnode );
              compiler_emit( compiler, px, "\teN\n", &var_offset, ident );
          } else {
              yyerrorf( "name '%s' not declared in the current scope", ident );
          }
          freex( ident );
      }
  ;

bytecode_constant
  : __INTEGER_CONST
      {
          char *int_str = obtain_string_from_strpool( compiler->strpool, $1 );
	  ssize_t val = atol( int_str );
	  compiler_emit( compiler, px, "\te\n", &val );
          freex( int_str );
      }
  | '+' __INTEGER_CONST
      {
          char *int_str = obtain_string_from_strpool( compiler->strpool, $2 );
	  ssize_t val = atol( int_str );
	  compiler_emit( compiler, px, "\te\n", &val );
          freex( int_str );
      }
  | '-' __INTEGER_CONST
      {
          char *int_str = obtain_string_from_strpool( compiler->strpool, $2 );
	  ssize_t val = -atol( int_str );
	  compiler_emit( compiler, px, "\te\n", &val );
          freex( int_str );
      }
  | __REAL_CONST
      {
          char *real_str = obtain_string_from_strpool( compiler->strpool, $1 );
          double val;
          sscanf( real_str, "%lf", &val );
          compiler_emit( compiler, px, "\tf\n", val );
          freex( real_str );
      }
  | __STRING_CONST
      {
          char *strvalue = obtain_string_from_strpool( compiler->strpool, $1 );
          ssize_t string_offset;
          string_offset =
              compiler_assemble_static_string( compiler, strvalue, px );
          compiler_emit( compiler, px, "\te\n", &string_offset );
          freex( strvalue );
      }

  | __DOUBLE_PERCENT __IDENTIFIER
      {
          char *ident = obtain_string_from_strpool( compiler->strpool, $2 );
          static const ssize_t zero = 0;
          if( !compiler->current_function ) {
              yyerrorf( "type attribute '%%%%%s' is not available here "
                        "(are you compiling a function or operator?)", ident );
          } else {
              if( implementation_has_attribute( ident )) {
                  compiler_emit( compiler, px, "\te\n", &zero );

                  FIXUP *type_attribute_fixup =
                      new_fixup_absolute
                      ( ident, thrcode_length( compiler->thrcode ) - 1,
                        NULL /* next */, px );

                  dnode_insert_code_fixup( compiler->current_function,
                                           type_attribute_fixup );
              }
          }
          freex( ident );
      }

  | _CONST '(' constant_expression ')'
      {
	  const_value_t const_expr = $3;

	  switch( const_expr.value_type ) {
	  case VT_INTMAX: {
	      ssize_t val = const_expr.value.i;
	      compiler_emit( compiler, px, "\te\n", &val );
	      }
	      break;
	  case VT_FLOAT: {
	      double val = const_expr.value.f;
	      compiler_emit( compiler, px, "\tf\n", &val );
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
            char *ident = obtain_string_from_strpool( compiler->strpool, $1 );
	    compiler_check_and_push_function_name( compiler, NULL, ident, px );
            freex( ident );
	}
  | module_list __COLON_COLON __IDENTIFIER
	{
            char *ident = obtain_string_from_strpool( compiler->strpool, $3 );
	    compiler_check_and_push_function_name( compiler, $1, ident, px );
            freex( ident );
	}
  ;

multivalue_function_call
  : function_identifier 
        {
	  TNODE *fn_tnode;
          type_kind_t fn_kind;

	  fn_tnode = compiler->current_call ?
	      dnode_type( compiler->current_call ) : NULL;

	  compiler->current_arg = fn_tnode ?
              tnode_args( fn_tnode ) : NULL;

          fn_kind = fn_tnode ? tnode_kind( fn_tnode ) : TK_NONE;

          if( fn_kind == TK_FUNCTION_REF || fn_kind == TK_CLOSURE ) {
              compiler_push_typed_expression( compiler, share_tnode(fn_tnode), px );
          }

	  compiler_push_guarding_arg( compiler, px );
	}
    '(' opt_actual_argument_list ')'
        {
	    DNODE *function = compiler->current_call;
	    TNODE *fn_tnode = function ? dnode_type( function ) : NULL;
            type_kind_t fn_kind = fn_tnode ?
                tnode_kind( fn_tnode ) : TK_NONE;

	    if( fn_kind == TK_FUNCTION_REF || fn_kind == TK_CLOSURE ) {
		char *fn_name = dnode_name( function );
		ssize_t offset = dnode_offset( function );
		compiler_emit( compiler, px, "\tceN\n", PLD, &offset, fn_name );
	    }

	    $$ = compiler_compile_multivalue_function_call( compiler, px );
	}
  | lvalue 
        {
	  TNODE *fn_tnode = NULL;

	  compiler_compile_ldi( compiler, px );

	  compiler_emit( compiler, px, "\tc\n", RTOR );

	  fn_tnode = compiler->e_stack ?
	      enode_type( compiler->e_stack ) : NULL;

          compiler_push_current_interface_nr( compiler, px );
          compiler_push_current_call( compiler, px );

          compiler->current_interface_nr = 0;

	  compiler->current_call = new_dnode( px );

	  if( fn_tnode ) {
	      dnode_insert_type( compiler->current_call,
				 share_tnode( fn_tnode ));
	  }
	  if( fn_tnode && tnode_kind( fn_tnode ) != TK_FUNCTION_REF ) {
	      yyerrorf( "called object is not a function pointer" );
	  }

	  compiler->current_arg = fn_tnode ?
	      tnode_args( fn_tnode ) : NULL;

	  compiler_push_guarding_arg( compiler, px );
	}
    '(' opt_actual_argument_list ')'
        {
	    compiler_emit( compiler, px, "\tc\n", RFROMR );
	    $$ = compiler_compile_multivalue_function_call( compiler, px );
	}
  | variable_access_identifier
    __ARROW __IDENTIFIER opt_method_interface
        {
            DNODE *object = $1;
            TNODE *object_type = dnode_type( object );
            char  *method_name =
                obtain_string_from_strpool( compiler->strpool, $3 );
            TNODE *interface_type = $4;
            DNODE *method = NULL;
            int class_has_interface = 1;
            ssize_t interface_nr = 0;

            if( interface_type ) {
                char *interface_name = tnode_name( interface_type );
                assert( interface_name );
                if( tnode_kind( interface_type ) == TK_CLASS ) {
                    /* Look-up the base class used as an interface: */
                    ssize_t interface_count = 1;
                    TNODE *base_type = object_type;
                    while( base_type ) {
                        interface_count--;
                        if( base_type == interface_type ) {
                            interface_nr = interface_count;
                            break;
                        }
                        base_type = tnode_base_type( base_type );
                    }
                    if( interface_nr > 0 ) {
                        char *class_name =
                            object_type ? tnode_name( object_type ) : NULL;
                        if( class_name ) {
                            yyerrorf( "the caller class '%s' does not "
                                      "inherit class '%s'",
                                      class_name, interface_name );
                        } else {
                            yyerrorf( "the caller class does not "
                                      "inherit class '%s'",
                                      interface_name );
                        }
                    } else {
                        method = tnode_lookup_method( interface_type, method_name );
                    }
                } else {
                    class_has_interface =
                        tnode_lookup_interface( object_type, interface_name )
                        != NULL;
                    if( !class_has_interface ) {
                        char *class_name =
                            object_type ? tnode_name( object_type ) : NULL;
                        if( class_name ) {
                            yyerrorf( "the caller class '%s' does not "
                                      "implement interface '%s'",
                                      class_name, interface_name );
                        } else {
                            yyerrorf( "the caller class does not implement "
                                      "interface '%s'",
                                      interface_name );
                        }
                    } else {
                        method = tnode_lookup_method( interface_type, method_name );
                    }
                }
            } else {
                if( object_type ) {
                    method = tnode_lookup_method( object_type, method_name );
                }
            }

            compiler_push_current_interface_nr( compiler, px );
            compiler_push_current_call( compiler, px );

	    if( method ) {
		TNODE *fn_tnode = dnode_type( method );

                compiler->current_interface_nr = interface_nr;

		if( fn_tnode && tnode_kind( fn_tnode ) != TK_METHOD ) {
		    yyerrorf( "called field is not a method" );
                    compiler->current_call = NULL;
		} else {
                    compiler->current_call = share_dnode( method );
                }

                DNODE *first_arg = fn_tnode ?
                    tnode_args( fn_tnode ) : NULL;;

		compiler->current_arg = first_arg ?
		    dnode_next( first_arg ) : NULL;

	    } else if( object && class_has_interface ) {
		char *object_name = object ? dnode_name( object ) : NULL;
		char *class_name =
		    object_type ? tnode_name( object_type ) : NULL;

		if( object_name && method_name ) {
                    char *interface_name = interface_type ?
                        tnode_name( interface_type ) : NULL;
                    if( interface_name ) { 
                        yyerrorf( "object '%s' does not have method '%s@%s'",
                                  object_name, method_name, interface_name );
                    } else {
                        yyerrorf( "object '%s' does not have method '%s'",
                                  object_name, method_name );
                    }
		} else if ( class_name && method_name ) {
                    char *interface_name = interface_type ?
                        tnode_name( interface_type ) : NULL;
                    if( interface_name ) {
                        yyerrorf( "type/class '%s' does not have method '%s@%s'",
                                  class_name, method_name, interface_name );
                    } else {
                        yyerrorf( "type/class '%s' does not have method '%s'",
                                  class_name, method_name );
                    }
		} else {
		    yyerrorf( "can not locate method '%s'", method_name );
		}
	    }
	    compiler_push_guarding_arg( compiler, px );
	    compiler_compile_load_variable_value( compiler, object, px );
            freex( method_name );
	}
    '(' opt_actual_argument_list ')'
        {
            compiler_emit_default_arguments( compiler, NULL, px );
	    compiler_compile_load_variable_value( compiler, $1, px );
	    compiler_drop_top_expression( compiler );
	    $$ = compiler_compile_multivalue_function_call( compiler, px );
	}

  | lvalue 
        {
	    compiler_compile_ldi( compiler, px );
            compiler_compile_dup( compiler, px );
            compiler_emit( compiler, px, "\tc\n", RTOR );
	    compiler_drop_top_expression( compiler );
	}
    __ARROW __IDENTIFIER opt_method_interface
        {
            ENODE *object_expr = compiler->e_stack;;
            TNODE *object_type =
		object_expr ? enode_type( object_expr ) : NULL;
            char  *method_name =
                obtain_string_from_strpool( compiler->strpool, $4 );
            TNODE *interface_type = $5;
            DNODE *method = NULL;
            int class_has_interface = 1;
            ssize_t interface_nr = 0;

            if( !object_expr ) {
                yyerrorf( "too little values on the evaluation stack "
                          "to call a method" );
            }

            if( interface_type ) {
                char *interface_name = tnode_name( interface_type );
                assert( interface_name );
                if( tnode_kind( interface_type ) == TK_CLASS ) {
                    /* Look-up the base class used as an interface: */
                    ssize_t interface_count = 1;
                    TNODE *base_type = object_type;
                    while( base_type ) {
                        interface_count--;
                        if( base_type == interface_type ) {
                            interface_nr = interface_count;
                            break;
                        }
                        base_type = tnode_base_type( base_type );
                    }
                    if( interface_nr > 0 ) {
                        char *class_name =
                            object_type ? tnode_name( object_type ) : NULL;
                        if( class_name ) {
                            yyerrorf( "the caller class '%s' does not "
                                      "inherit class '%s'",
                                      class_name, interface_name );
                        } else {
                            yyerrorf( "the caller class does not "
                                      "inherit class '%s'",
                                      interface_name );
                        }
                    } else {
                        method = tnode_lookup_method( interface_type, method_name );
                    }
                } else {
                    class_has_interface =
                        tnode_lookup_interface( object_type, interface_name )
                        != NULL;
                    if( !class_has_interface ) {
                        char *class_name =
                            object_type ? tnode_name( object_type ) : NULL;
                        if( class_name ) {
                            yyerrorf( "the caller class '%s' does not "
                                      "implement interface '%s'",
                                      class_name, interface_name );
                        } else {
                            yyerrorf( "the caller class does not implement "
                                  "interface '%s'",
                                      interface_name );
                        }
                    } else {
                        method = tnode_lookup_method( interface_type, method_name );
                    }
                }
            } else {
                if( object_type ) {
                    method = tnode_lookup_method( object_type, method_name );
                }
            }

            compiler_push_current_interface_nr( compiler, px );
            compiler_push_current_call( compiler, px );

	    if( method ) {
		TNODE *fn_tnode = dnode_type( method );

                compiler->current_interface_nr = interface_nr;

		compiler->current_call = share_dnode( method );

		if( fn_tnode && tnode_kind( fn_tnode ) != TK_METHOD ) {
		    yyerrorf( "called field is not a method" );
		}

                DNODE *first_arg = fn_tnode ?
                    tnode_args( fn_tnode ) : NULL;;

		compiler->current_arg = first_arg ?
		    dnode_next( first_arg ) : NULL;

	    } else if( object_expr && class_has_interface ) {
                char *interface_name = interface_type ?
                    tnode_name( interface_type ) : NULL;
		char *class_name =
		    object_type ? tnode_name( object_type ) : NULL;

                if( interface_name ) {
		    yyerrorf( "interface '%s' does not have method '%s'",
			      interface_name, method_name );
                } else if ( class_name && method_name ) {
		    yyerrorf( "type/class '%s' does not have method '%s'",
			      class_name, method_name );
		} else {
		    yyerrorf( "can not locate method '%s'", method_name );
		}
	    }
            compiler_push_guarding_arg( compiler, px );
            compiler_swap_top_expressions( compiler );
            freex( method_name );
	}
    '(' opt_actual_argument_list ')'
        {
	    compiler_emit( compiler, px, "\tc\n", RFROMR );
	    $$ = compiler_compile_multivalue_function_call( compiler, px );
	}

  ;

function_call
  : multivalue_function_call
    {
	if( $1 > 0 ) {
	    compiler_emit_drop_returned_values( compiler, $1 - 1, px );
	} else {
	    yyerrorf( "functions called in exressions must return "
		      "at least one value" );
	    /* Push NULL value to maintain stack value balance and
	       avoid segfaults or asserts in the downstream code: */
	    compiler_push_typed_expression( compiler, new_tnode_nullref( px ), px );
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
	compiler_convert_function_argument( compiler, px );
      }
  | __IDENTIFIER 
      {
          char *argument_name =
              obtain_string_from_strpool( compiler->strpool, $1 );
          TNODE *current_function_type =
              compiler->current_call ?
              dnode_type( compiler->current_call ) : NULL;

          if( current_function_type &&
              tnode_lookup_argument( current_function_type, argument_name )) {
              compiler_emit_default_arguments( compiler, argument_name, px );
          } else {
              char *function_name =
                  compiler->current_call ?
                  dnode_name( compiler->current_call ) : NULL;
              yyerrorf( "function '%s' does not have argument '%s'",
                        function_name, argument_name );
          }
          freex( argument_name );
      }
   __THICK_ARROW expression
      {
	compiler_convert_function_argument( compiler, px );
      }
  | actual_argument_list ',' expression
      {
	compiler_convert_function_argument( compiler, px );
      }
  | actual_argument_list ',' __IDENTIFIER
      {
          char *ident = obtain_string_from_strpool( compiler->strpool, $3 );
	  compiler_emit_default_arguments( compiler, ident, px );
          freex( ident );
      }
    __THICK_ARROW expression
      {
	  compiler_convert_function_argument( compiler, px );
      }
  ;

expression_list
  : expression
      { $$ = 1; }
  | expression_list ',' expression
      { $$ = $1 + 1; }
  ;

stdio_inpupt_condition
: '<' '>'
{
    cexception_t inner;
    TNODE *string_tnode = typetab_lookup( compiler->typetab, "string" );
    TNODE *volatile type_tnode = string_tnode;
    DNODE *volatile default_var = NULL;
    DNODE *volatile shared_default_var = NULL;
    ssize_t default_var_offset = 0;

    cexception_guard( inner ) {
        share_tnode( type_tnode );
        default_var = new_dnode_typed( "$_", type_tnode, &inner );
        dnode_assign_offset( default_var, &compiler->local_offset );
        type_tnode = NULL;

        shared_default_var = share_dnode( default_var );
        compiler_vartab_insert_named_vars( compiler, &shared_default_var, &inner );
        default_var_offset = dnode_offset( default_var );

        compiler->local_offset ++;
        type_tnode = share_tnode( string_tnode );
        default_var = new_dnode_typed( "$ARG", type_tnode, &inner );
        dnode_assign_offset( default_var, &compiler->local_offset );
        type_tnode = NULL;
        compiler_vartab_insert_named_vars( compiler, &default_var, &inner );

        share_tnode( string_tnode );
        compiler_push_typed_expression( compiler, string_tnode, &inner );
        compiler_emit( compiler, &inner, "\tc\n", STDREAD );
        compiler_emit( compiler, &inner, "\tc\n", DUP );
        compiler_emit( compiler, &inner, "\tce\n", PST, &default_var_offset );        
    }
    cexception_catch {
        delete_tnode( type_tnode );
        delete_dnode( shared_default_var );
        delete_dnode( default_var );
        cexception_reraise( inner, px );
    }
    delete_tnode( type_tnode );
    delete_dnode( default_var );
}
;

file_input_condition
:'<' expression '>'
  {
      cexception_t inner;
      TNODE *string_type = typetab_lookup( compiler->typetab, "string" );
      TNODE *volatile type_tnode = string_type;
      DNODE *volatile default_var = NULL;
      ssize_t default_var_offset = 0;

      cexception_guard( inner ) {
          share_tnode( type_tnode );
          default_var = new_dnode_typed( "$_", type_tnode, &inner );
          dnode_assign_offset( default_var, &compiler->local_offset );
          type_tnode = NULL;
          default_var_offset = dnode_offset( default_var );
          compiler_vartab_insert_named_vars( compiler, &default_var, &inner );

          compiler->local_offset ++;
          type_tnode = share_tnode( string_type );
          default_var = new_dnode_typed( "$ARG", type_tnode, &inner );
          dnode_assign_offset( default_var, &compiler->local_offset );
          type_tnode = NULL;
          compiler_vartab_insert_named_vars( compiler, &default_var, &inner );

          compiler_drop_top_expression( compiler );
          type_tnode = share_tnode( string_type );
          compiler_push_typed_expression( compiler, string_type, &inner );
      }
      cexception_catch {
          delete_tnode( type_tnode );
          delete_dnode( default_var );
          cexception_reraise( inner, px );
      }
      delete_tnode( type_tnode );
      delete_dnode( default_var );

      compiler_emit( compiler, px, "\tcI\n", LDC, '\n' );
      compiler_emit( compiler, px, "\tccc\n", SFILEREADLN, SWAP, DROP );
      compiler_emit( compiler, px, "\tc\n", DUP );
      compiler_emit( compiler, px, "\tce\n", PST, &default_var_offset );        
  }
;

condition
  : function_call
  | simple_expression
  | file_input_condition
  | '(' file_input_condition ')'
  | stdio_inpupt_condition
  | '(' stdio_inpupt_condition ')'
/*
  | arithmetic_expression
*/
  | boolean_expression
  | '(' simple_expression ')'
  | '(' function_call ')'
  ;

multivalue_expression_list
  : multivalue_function_call
      { $$ = $1; }
  | expression ',' expression_list
      { $$ = $3 + 1; }
  ;

io_expression
  : '<' expression '>'
  {
      cexception_t inner;
      TNODE *string_type = typetab_lookup( compiler->typetab, "string" );
      compiler_drop_top_expression( compiler );
      compiler_emit( compiler, px, "\tcI\n", LDC, '\n' );
      compiler_emit( compiler, px, "\tccc\n", SFILEREADLN, SWAP, DROP );
      cexception_guard( inner ) {
          share_tnode( string_type );
          compiler_push_typed_expression( compiler, string_type, &inner );
      }
      cexception_catch {
          delete_tnode( string_type );
          cexception_reraise( inner, px );
      }
  }
  | '<' '>'
  {
    cexception_t inner;
    TNODE *type_tnode = typetab_lookup( compiler->typetab, "string" );

    cexception_guard( inner ) {
        compiler_push_typed_expression( compiler, type_tnode, &inner );
        compiler_emit( compiler, &inner, "\tc\n", STDREAD );
    }
    cexception_catch {
        delete_tnode( type_tnode );
        cexception_reraise( inner, px );
    }
  }
;

expression
  : function_call
  | simple_expression
  | arithmetic_expression
  | boolean_expression
  | assignment_expression
  | null_expression
  | io_expression
  ;

null_expression
  : _NULL
      {
	  TNODE *tnode = new_tnode_nullref( px );
	  compiler_push_typed_expression( compiler, tnode, px );
	  compiler_emit( compiler, px, "\tc\n", PLDZ );
      }
  ;

opt_closure_initialisation_list
: __IDENTIFIER '{' closure_initialisation_list opt_semicolon '}'
{
    $$ = $1;
}
| /* empty */
{
    $$ = -1;
}
;

closure_initialisation_list
: closure_initialisation
| closure_initialisation_list ';' closure_initialisation
;

closure_var_declaration
  : opt_variable_declaration_keyword
    identifier ':' var_type_description
      {
       int readonly = $1;
       if( readonly ) {
           dnode_list_set_flags( $2, DF_IS_READONLY );
       }
       $$ = dnode_list_append_type( $2, $4 );
      }

  | opt_variable_declaration_keyword
    var_type_description variable_declarator
      {
        int readonly = $1;
        if( readonly ) {
            dnode_list_set_flags( $3, DF_IS_READONLY );
        }
        $$ = dnode_list_append_type( $3, $2 );
      }

  ;

closure_var_list_declaration
  : opt_variable_declaration_keyword
    identifier ',' identifier_list ':' var_type_description
      {
       int readonly = $1;
       DNODE *variables = dnode_append( $2, $4 );
       if( readonly ) {
           dnode_list_set_flags( variables, DF_IS_READONLY );
       }
       $$ = dnode_list_append_type( variables, $6 );
      }

  | opt_variable_declaration_keyword
    var_type_description
    variable_declarator ',' uninitialised_var_declarator_list
      {
        int readonly = $1;
        DNODE *variables = dnode_append( $3, $5 );
        if( readonly ) {
            dnode_list_set_flags( variables, DF_IS_READONLY );
        }
        $$ = dnode_list_append_type( variables, $2 );
      }

  ;

closure_initialisation
: closure_var_declaration
{
    ENODE *top_expr = compiler->e_stack;
    TNODE *closure_tnode = top_expr ? enode_type( top_expr ) : NULL;
    DNODE *closure_var = $1;
    TNODE *var_type = closure_var ? dnode_type( closure_var ) : NULL;
    ssize_t offset = 0;

    assert( closure_tnode );
    assert( var_type );

    tnode_insert_fields( closure_tnode, closure_var );
    offset = dnode_offset( closure_var );
    compiler_emit( compiler, px, "\tce\n", OFFSET, &offset );
    compiler_push_typed_expression( compiler,
                     new_tnode_addressof( share_tnode( var_type ), px ), 
                     px );
}
 '=' expression
{
    compiler_compile_sti( compiler, px );
    compiler_emit( compiler, px, "\tc\n", DUP );
}

| closure_var_list_declaration
{
    ENODE *top_expr = compiler->e_stack;
    TNODE *closure_tnode = top_expr ? enode_type( top_expr ) : NULL;
    DNODE *closure_var_list = $1;
    DNODE *closure_var;
    ssize_t offset = 0;
    int first_variable = 1;

    assert( closure_tnode );

    tnode_insert_fields( closure_tnode, closure_var_list );

    foreach_dnode( closure_var, closure_var_list ) {

        if( !first_variable ) {
            share_tnode( closure_tnode );
        }
        offset = dnode_offset( closure_var );
        compiler_emit( compiler, px, "\tce\n", OFFSET, &offset );
        compiler_emit( compiler, px, "\tc\n", RTOR );
        compiler_emit( compiler, px, "\tc\n", DUP );
        first_variable = 0;
    }
}
 '=' multivalue_expression_list
{
    DNODE *var_list = $1;
    DNODE *var;
    ssize_t value_count = $4;
    ssize_t variable_count = dnode_list_length( var_list );

    if( variable_count > value_count ) {
        yyerrorf( "too little values (%d) to initialise "
                  "%d closure variables", value_count, variable_count );
    } else {
        if( variable_count < value_count ) {
            if( variable_count == value_count - 1 ) {
                compiler_compile_drop( compiler, px );
            } else {
                compiler_compile_dropn( compiler, value_count - variable_count,
                                        px );
            }
        }
    }

    variable_count = 0;
    foreach_dnode( var, var_list ) {
        variable_count ++;
        if( variable_count <= value_count ) {
            TNODE *var_type = var ? dnode_type( var ) : NULL;

            assert( var_type );

            compiler_emit( compiler, px, "\tc\n", RFROMR );
            compiler_push_typed_expression( compiler,
                             new_tnode_addressof( share_tnode( var_type ),
                                                  px ), 
                             px );
            compiler_compile_swap( compiler, px );
            compiler_compile_sti( compiler, px );
        }
    }
}

| opt_variable_declaration_keyword identifier
{
    int readonly = $1;
    DNODE *closure_var = $2;

    if( readonly ) {
        dnode_list_set_flags( closure_var, DF_IS_READONLY );
    }
}
 '=' expression
{
    ENODE *top_expr = compiler->e_stack;
    TNODE *top_type = top_expr ? enode_type( top_expr ) : NULL;
    ENODE *second_expr = enode_next( compiler->e_stack );
    TNODE *closure_tnode = second_expr ? enode_type( second_expr ) : NULL;
    DNODE *closure_var = $2;
    ssize_t offset = 0;

    assert( closure_tnode );
    assert( top_type );

    dnode_insert_type( closure_var, share_tnode( top_type ));
    tnode_insert_fields( closure_tnode, closure_var );
    offset = dnode_offset( closure_var );
    compiler_emit( compiler, px, "\tc\n", SWAP );
    compiler_emit( compiler, px, "\tce\n", OFFSET, &offset );
    compiler_emit( compiler, px, "\tc\n", SWAP );

    compiler_push_typed_expression( compiler,
                     new_tnode_addressof( share_tnode( top_type ), px ), 
                     px );

    compiler_swap_top_expressions( compiler );

    compiler_compile_sti( compiler, px );
    compiler_emit( compiler, px, "\tc\n", DUP );
}

| opt_variable_declaration_keyword identifier ','
  identifier_list
{
    int readonly = $1;
    DNODE *closure_var_list = dnode_append( $2, $4 );

    if( readonly ) {
        dnode_list_set_flags( closure_var_list, DF_IS_READONLY );
    }

    compiler_emit( compiler, px, "\tc\n", RTOR );
}
 '=' multivalue_expression_list
{
    ENODE *top_expr = compiler->e_stack;
    ENODE *current_expr, *closure_expr;
    TNODE *closure_tnode;
    DNODE *closure_var_list = $2;
    ssize_t len = dnode_list_length( closure_var_list );
    ssize_t expr_nr = $7;
    ssize_t offset = 0;
    int i;
    DNODE *var;

    closure_expr = top_expr;
    for( i = 0; i < expr_nr; i++ ) {
        closure_expr = enode_next( closure_expr );
    }

    closure_tnode = closure_expr ? enode_type( closure_expr ) : NULL;
    
    assert( closure_tnode );

    current_expr = top_expr;
    foreach_reverse_dnode( var, closure_var_list ) {
        TNODE *expr_type = current_expr ?
            share_tnode( enode_type( current_expr )) : NULL;
        type_kind_t expr_type_kind = expr_type ?
            tnode_kind( expr_type ) : TK_NONE;
        if( expr_type_kind == TK_FUNCTION ||
            expr_type_kind == TK_OPERATOR ||
                 expr_type_kind == TK_METHOD ) {
            TNODE *base_type = typetab_lookup( compiler->typetab, "procedure" );
            expr_type = new_tnode_function_or_proc_ref
                ( share_dnode( tnode_args( expr_type )),
                  share_dnode( tnode_retvals( expr_type )),
                  share_tnode( base_type ),
                  px );
        }
        dnode_append_type( var, expr_type );
        current_expr = current_expr ? enode_next( current_expr ) : NULL;
    }

    tnode_insert_fields( closure_tnode, closure_var_list );

    if( expr_nr < len ) {
        yyerrorf( "number of expressions (%d) is less than "
                  "is needed to initialise %d variables",
                  expr_nr, len );
    }

    if( expr_nr > len ) {
        if( expr_nr == len + 1 ) {
            compiler_compile_drop( compiler, px );
        } else {
            compiler_compile_dropn( compiler, expr_nr - len, px );
        }
    }

    i = 0;
    foreach_reverse_dnode( var, closure_var_list ) {
        i ++;
        if( i > len ) break;
        if( i <= expr_nr ) {
            TNODE *var_type = var ? dnode_type( var ) : NULL;

            assert( var_type );

            compiler_push_typed_expression( compiler,
                             new_tnode_addressof( share_tnode( var_type ),
                                                  px ), 
                             px );

            compiler_emit( compiler, px, "\tc\n", RFROMR );
            compiler_emit( compiler, px, "\tc\n", DUP );
            compiler_emit( compiler, px, "\tc\n", RTOR );
            offset = dnode_offset( var );
            compiler_emit( compiler, px, "\tce\n", OFFSET, &offset );
            compiler_compile_swap( compiler, px );
            compiler_compile_sti( compiler, px );
        }
    }

    compiler_emit( compiler, px, "\tc\n", RFROMR );
}

;

function_expression_header
:   opt_function_attributes function_or_procedure_keyword '(' argument_list ')'
         opt_retval_description_list
    {
        dlist_push_dnode( &compiler->loop_stack, &compiler->loops, px );
        $$ = new_dnode_function( /* name = */ NULL,
                                 /* parameters = */ $4,
                                 /* return_values = */ $6,
                                 px );
        if( $1 & DF_BYTECODE )
            dnode_set_flags( $$, DF_BYTECODE );
        if( $1 & DF_INLINE )
            dnode_set_flags( $$, DF_INLINE );
    }
;

opt_function_or_procedure_keyword
: function_or_procedure_keyword
| /* empty */
    { $$ = 1; }
;

closure_header
: _CLOSURE
  opt_function_or_procedure_keyword '(' argument_list ')'
      opt_retval_description_list
      {
          TNODE *closure_tnode = new_tnode_ref( px );
          DNODE *closure_fn_ref = NULL;
          ssize_t zero = 0;
          /* Allocate the closure structure: */
          compiler_push_absolute_fixup( compiler, px );
          compiler_emit( compiler, px, "\tc", ALLOC );
          compiler_push_absolute_fixup( compiler, px );
          compiler_emit( compiler, px, "ee\n", &zero, &zero );
          compiler_emit( compiler, px, "\tc\n", DUP );
          tnode_set_kind( closure_tnode, TK_STRUCT );
          /* reserve one stackcell for a function pointer of the
             closure: */
          closure_fn_ref = new_dnode_typed( "",  new_tnode_ref( px ), px );
          tnode_insert_fields( closure_tnode, closure_fn_ref );
          compiler_push_typed_expression( compiler, closure_tnode, px );
      }
      opt_closure_initialisation_list
      {
          char *closure_name =
              obtain_string_from_strpool( compiler->strpool, $8 );
          DNODE *parameters = $4;
          DNODE *return_values = $6;
          DNODE *self_dnode = new_dnode_name( closure_name, px );
          ENODE *closure_expr = compiler->e_stack;
          TNODE *closure_type = enode_type( closure_expr );

          ssize_t nref, size;

          nref = tnode_number_of_references( closure_type );
          size = tnode_size( closure_type );

          compiler_fixup( compiler, nref );
          compiler_fixup( compiler, size );

          dnode_insert_type( self_dnode, share_tnode( closure_type ));

          parameters = dnode_append( parameters, self_dnode );
          self_dnode = NULL;
        
          dlist_push_dnode( &compiler->loop_stack, &compiler->loops, px );

          $$ = new_dnode_function( /* name = */ NULL, 
                                   parameters, return_values, px );
          tnode_set_kind( dnode_type( $$ ), TK_CLOSURE );
          freex( closure_name );
    }
;

function_expression
:   function_expression_header
    function_or_operator_start
    function_or_operator_body
    function_or_operator_end
    {
        compiler->loops = dlist_pop_data( &compiler->loop_stack );
        compiler_compile_load_function_address( compiler, $1, px );
    }

| closure_header
  function_or_operator_start
  function_or_operator_body
  function_or_operator_end
    {
        ENODE *closure_expr = enode_list_pop( &compiler->e_stack );
        TNODE *closure_type = enode_type( closure_expr );
        DNODE *fields = tnode_fields( closure_type );
        ssize_t offs = dnode_offset( fields );

        /* assert( offs == -sizeof(alloccell_t)-sizeof(void*) ); */

        compiler->loops = dlist_pop_data( &compiler->loop_stack );
        compiler_emit( compiler, px, "\tce\n", OFFSET, &offs );
        compiler_compile_load_function_address( compiler, $1, px );
        compiler_emit( compiler, px, "\tc\n", PSTI );
        delete_enode( closure_expr );
    }
;

simple_expression
  : constant
  | variable
  | field_access
      {
	compiler_compile_ldi( compiler, px );
      }
  | indexed_rvalue
  | _BYTECODE ':' var_type_description '{' bytecode_sequence '}'
      {
	compiler_push_typed_expression( compiler, $3, px );
      }
  | generator_new
  | array_expression
  | struct_expression
  | unpack_expression
  | function_expression
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
	  compiler_check_and_compile_operator( compiler,
					    tnode_element_type( type ),
					    "unpackarray", 3 /* arity */,
					    NULL /* fixup_values */, px );
      } else {
	  compiler_check_and_compile_operator( compiler, type,
					    "unpack", 3 /* arity */,
					    NULL /* fixup_values */, px );
      }
      compiler_emit( compiler, px, "\n" );
  }
  | _UNPACK compact_type_description '[' ']'
    '(' expression ',' expression ',' expression ')'
  {
      TNODE *element_type = $2;
      compiler_check_and_compile_operator( compiler, element_type,
					"unpackarray", 3 /* arity */,
					NULL /* fixup_values */, px );

      compiler_emit( compiler, px, "\n" );
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
	  new_tnode_array_snail( NULL, compiler->typetab, px );

      if( compiler_lookup_operator( compiler, element_type, operator_name,
                                    arity, px )) {
          key_value_t *fixup_values =
              make_mdalloc_key_value_list( element_type, level );
	  compiler_check_and_compile_operator( compiler, element_type,
					    operator_name,
					    arity, fixup_values,
					    px );
	  /* Return value pushed by ..._compile_operator() function must
	     be dropped, since it only describes return value as having
	     type 'array'. The caller of the current function will push
	     a correct return value 'array of proper_element_type' */
	  compiler_drop_top_expression( compiler );
	  if( compiler_stack_top_is_array( compiler )) {
	      compiler_append_expression_type( compiler, array_tnode );
	      compiler_append_expression_type( compiler, share_tnode( element_type ));
	  }
      } else {
	  compiler_drop_top_expression( compiler );
	  compiler_drop_top_expression( compiler );
	  compiler_drop_top_expression( compiler );
	  tnode_report_missing_operator( element_type, operator_name, arity );
      }
      compiler_emit( compiler, px, "\n" );
  }
  ;

array_expression
  : '[' expression_list opt_comma ']'
     {
	 compiler_compile_array_expression( compiler, $2, px );
     }
  /* Array 'comprehensions' (aka array 'for' epxressions): */
  | '[' labeled_for lvariable
     {
         char *label = obtain_string_from_strpool( compiler->strpool, $2 );
         compiler_push_loop( compiler, label, 2, px );
         dnode_set_flags( compiler->loops, DF_LOOP_HAS_VAL );
         compiler_compile_dup( compiler, px );
         freex( label );
     }
     '=' expression
     {
         compiler_compile_sti( compiler, px );
     }
     _TO expression ':'
     {
         /* ..., loop_counter_addr, loop_limit */
         compiler_compile_dup( compiler, px );
         /* ..., loop_counter_addr, loop_limit, loop_limit */
         compiler_compile_unop( compiler, "++", px );
         /* ..., loop_counter_addr, loop_limit, array_length */
         compiler_emit( compiler, px, "\n" );

         /* Compile loop zero length check: */
         compiler_compile_peek( compiler, 3, px );
         compiler_compile_ldi( compiler, px );
         compiler_compile_peek( compiler, 3, px );
         if( compiler_test_top_types_are_identical( compiler, px )) {
             compiler_compile_binop( compiler, ">", px );
             compiler_push_relative_fixup( compiler, px );
             compiler_compile_jnz( compiler, 0, px );
         } else {
             ssize_t zero = 0;
             compiler_drop_top_expression( compiler );
             compiler_drop_top_expression( compiler );
             compiler_push_relative_fixup( compiler, px );
             compiler_emit( compiler, px, "\tce\n", JMP, &zero );
         }
         compiler_emit( compiler, px, "\n" );

         compiler_push_thrcode( compiler, px );
     }
     expression ']'
     {
         /* Compile array allocation: */
         ENODE *element_expr = compiler->e_stack;
         TNODE *element_type = element_expr ? enode_type( element_expr ) : NULL;
         compiler_swap_thrcodes( compiler );
         compiler_compile_array_alloc( compiler, element_type, px );
         /* ..., loop_counter_addr, loop_limit, array */
         compiler_compile_rot( compiler, px );
         compiler_emit( compiler, px, "\n" );
         /* ..., array, loop_counter_addr, loop_limit */
         /* Will return here in the next loop iteration: */
         compiler_push_current_address( compiler, px );
         compiler_merge_top_thrcodes( compiler, px );
         /* ..., array, loop_counter_addr, loop_limit, element_expression */
         compiler_emit( compiler, px, "\n" );

         /* Store array element:*/

         /* Runtime stack configuration at this point: */
         /* ..., array, loop_counter_addr, loop_limit, expression_value */
         compiler_compile_peek( compiler, 4, px );
         /* ..., array, loop_counter_addr, loop_limit, expression_value, array */
         compiler_compile_peek( compiler, 4, px );
         /* ..., array, loop_counter_addr, loop_limit, expression_value,
            array, loop_counter_addr */
         compiler_compile_ldi( compiler, px );
         /* ..., array, loop_counter_addr, loop_limit, expression_value,
            array, loop_counter */
         compiler_compile_address_of_indexed_element( compiler, px );
         /* ..., array, loop_counter_addr, loop_limit, expression_value,
            element_address */
         compiler_compile_swap( compiler, px );
         /* ..., array, loop_counter_addr, loop_limit,
            element_address, expression_value */
         compiler_compile_sti( compiler, px );
         /* ..., array, loop_counter_addr, loop_limit */
         
         /* Finish the comprehension 'for' loop: */
         compiler_fixup_here( compiler );
         compiler_fixup_op_continue( compiler, px );
         compiler_compile_loop( compiler, compiler_pop_offset( compiler, px ), px );
         compiler_fixup_op_break( compiler, px );
         compiler_pop_loop( compiler );
         compiler_end_subscope( compiler, px );
     }

| '[' labeled_for lvariable
  {
      char * label = obtain_string_from_strpool( compiler->strpool, $2 );
      compiler_push_loop( compiler, /* loop_label = */ label,
                          /* ncounters = */ 2, px );
      dnode_set_flags( compiler->loops, DF_LOOP_HAS_VAL );
      freex( label );
      /* stack now: ..., lvariable_address */
  }
    _IN expression
  {
      /* stack now: ..., lvariable_address, array_last_ptr == array */
      compiler_push_thrcode( compiler, px );
  }
 ':' expression ']'
  {
      /* Compile array allocation: */
      compiler_swap_thrcodes( compiler );
      compiler_compile_dup( compiler, px );
      compiler_emit( compiler, px, "\tc\n", CLONE );
      /* ..., lvariable_address, array_last_ptr == array, new_array */
      compiler_compile_rot( compiler, px );
      /* ..., new_array, lvariable_address, array_last_ptr */
      /* Will return here in the next loop iteration: */
      compiler_push_current_address( compiler, px );
        
      /* Store the current array element into the loop variable: */
      compiler_compile_over( compiler, px );
      compiler_compile_over( compiler, px );
      compiler_make_stack_top_element_type( compiler );
      compiler_make_stack_top_addressof( compiler, px );
      compiler_compile_ldi( compiler, px );
      compiler_compile_sti( compiler, px );
        
      compiler_emit( compiler, px, "\n" );
      /* ..., new_array, lvariable_address, array_last_ptr */

      compiler_merge_top_thrcodes( compiler, px );
      /* ..., new_array, lvariable_address, array_last_ptr, expression */

      /* Store array element: */
      compiler_compile_peek( compiler, 4, px );
      compiler_make_stack_top_element_type( compiler );
      compiler_make_stack_top_addressof( compiler, px );
      compiler_compile_swap( compiler, px );
      compiler_compile_sti( compiler, px );
      /* ..., new_array, lvariable_address, array_last_ptr */
      /* Advance the target array pointer: */
      compiler_compile_rot( compiler, px );
      compiler_compile_rot( compiler, px );
      /* ..., lvariable_address, array_last_ptr, new_array */
      compiler_emit( compiler, px, "\tcIc\n", LDC, 1, INDEX );

      compiler_compile_rot( compiler, px );
      /* ..., new_array, lvariable_address, array_last_ptr */

      /* Finish the comprehension 'for' loop: */
      // compiler_fixup_here( compiler );
      compiler_fixup_op_continue( compiler, px );
      compiler_compile_next( compiler, compiler_pop_offset( compiler, px ),
                             px );
      compiler_fixup_op_break( compiler, px );
      compiler_pop_loop( compiler );
      compiler_end_subscope( compiler, px );
      compiler_emit( compiler, px, "\tc\n", ZEROOFFSET );
  }
  
  | '[' labeled_for variable_declaration_keyword for_variable_declaration
    {
        char *label = obtain_string_from_strpool( compiler->strpool, $2 );
        int readonly = $3;
	if( readonly ) {
	    dnode_set_flags( $4, DF_IS_READONLY );
	}
	compiler_push_loop( compiler, label, 2, px );
	dnode_set_flags( compiler->loops, DF_LOOP_HAS_VAL );
        freex( label );
    }
  '=' expression
    {
	DNODE *volatile loop_counter = $4;
        DNODE *volatile shared_loop_counter = NULL;

        cexception_t inner;
        cexception_guard( inner ) {
            if( dnode_type( loop_counter ) == NULL ) {
                dnode_append_type( loop_counter,
                                   share_tnode( enode_type( compiler->e_stack )));
                dnode_assign_offset( loop_counter, &compiler->local_offset );
            }
            shared_loop_counter = share_dnode( loop_counter );
            compiler_vartab_insert_named_vars( compiler, &shared_loop_counter,
                                               &inner );
            compiler_compile_store_variable( compiler, loop_counter, &inner );
            compiler_compile_load_variable_address( compiler, loop_counter,
                                                    &inner );
        }
        cexception_catch {
            delete_dnode( loop_counter );
            delete_dnode( shared_loop_counter );
            cexception_reraise( inner, px );
        }
        delete_dnode( loop_counter );
        delete_dnode( shared_loop_counter );
    }
     _TO expression ':'
    {
        /* ..., loop_counter_addr, loop_limit */
        compiler_compile_dup( compiler, px );
        /* ..., loop_counter_addr, loop_limit, loop_limit */
        compiler_compile_unop( compiler, "++", px );
        /* ..., loop_counter_addr, loop_limit, array_length */
        compiler_emit( compiler, px, "\n" );
         
        /* Compile loop zero length check: */
        compiler_compile_peek( compiler, 3, px );
        compiler_compile_ldi( compiler, px );
        compiler_compile_peek( compiler, 3, px );
        if( compiler_test_top_types_are_identical( compiler, px )) {
            compiler_compile_binop( compiler, ">", px );
            compiler_push_relative_fixup( compiler, px );
            compiler_compile_jnz( compiler, 0, px );
        } else {
            ssize_t zero = 0;
            compiler_drop_top_expression( compiler );
            compiler_drop_top_expression( compiler );
            compiler_push_relative_fixup( compiler, px );
            compiler_emit( compiler, px, "\tce\n", JMP, &zero );
        }
        compiler_emit( compiler, px, "\n" );

        compiler_push_thrcode( compiler, px );
    }
     expression ']'
    {
        /* Compile array allocation: */
        ENODE *element_expr = compiler->e_stack;
        TNODE *element_type = element_expr ? enode_type( element_expr ) : NULL;
        compiler_swap_thrcodes( compiler );
        compiler_compile_array_alloc( compiler, element_type, px );
        /* ..., loop_counter_addr, loop_limit, array */
        compiler_compile_rot( compiler, px );
        compiler_emit( compiler, px, "\n" );
        /* ..., array, loop_counter_addr, loop_limit */
        compiler_push_current_address( compiler, px );
        compiler_merge_top_thrcodes( compiler, px );
        /* ..., array, loop_counter_addr, loop_limit, element_expression */
        compiler_emit( compiler, px, "\n" );

        /* Store array element:*/

        /* Runtime stack configuration at this point: */
        /* ..., array, loop_counter_addr, loop_limit, expression_value */
        compiler_compile_peek( compiler, 4, px );
        /* ..., array, loop_counter_addr, loop_limit, expression_value, array */
        compiler_compile_peek( compiler, 4, px );
        /* ..., array, loop_counter_addr, loop_limit, expression_value,
           array, loop_counter_addr */
        compiler_compile_ldi( compiler, px );
        /* ..., array, loop_counter_addr, loop_limit, expression_value,
           array, loop_counter */
        compiler_compile_address_of_indexed_element( compiler, px );
        /* ..., array, loop_counter_addr, loop_limit, expression_value,
           element_address */
        compiler_compile_swap( compiler, px );
        /* ..., array, loop_counter_addr, loop_limit,
           element_address, expression_value */
        compiler_compile_sti( compiler, px );
        /* ..., array, loop_counter_addr, loop_limit */
         
        /* Finish the comprehension 'for' loop: */
        compiler_fixup_here( compiler );
        compiler_fixup_op_continue( compiler, px );
        compiler_compile_loop( compiler, compiler_pop_offset( compiler, px ), px );
        compiler_fixup_op_break( compiler, px );
        compiler_pop_loop( compiler );
        compiler_end_subscope( compiler, px );
    }

  | '[' labeled_for variable_declaration_keyword for_variable_declaration
    {
        char *label = obtain_string_from_strpool( compiler->strpool, $2 );
	int readonly = $3;
	if( readonly ) {
	    dnode_set_flags( $4, DF_IS_READONLY );
	}
	compiler_push_loop( compiler, /* loop_label = */ label,
                            /* ncounters = */ 1, px );
	dnode_set_flags( compiler->loops, DF_LOOP_HAS_VAL );
        freex( label );
    }
    _IN expression ':'
    {
        DNODE *volatile loop_counter_var = $4;
        TNODE *aggregate_expression_type = enode_type( compiler->e_stack );
        TNODE *element_type = 
            aggregate_expression_type ?
            tnode_element_type( aggregate_expression_type ) : NULL;

        if( enode_has_flags( compiler->e_stack, EF_IS_READONLY )) {
	    dnode_set_flags( loop_counter_var, DF_IS_READONLY );
        }

        if( element_type ) {
            if( dnode_type( loop_counter_var ) == NULL ) {
                dnode_append_type( loop_counter_var,
                                   share_tnode( element_type ));
            }
            dnode_assign_offset( loop_counter_var,
                                 &compiler->local_offset );
        }

        cexception_t inner;
        cexception_guard( inner ) {
            compiler_vartab_insert_named_vars( compiler, &loop_counter_var, &inner );
        }
        cexception_catch {
            delete_dnode( loop_counter_var );
            cexception_reraise( inner, px );
        }
        /* stack now: ..., array_current_ptr == array */
        compiler_push_thrcode( compiler, px );
    }
    expression ']'
    {
        /* Compile array allocation: */
        compiler_swap_thrcodes( compiler );
        compiler_compile_dup( compiler, px );
        compiler_emit( compiler, px, "\tc\n", CLONE );
        /* ..., array_last_ptr == array, new_array */
        compiler_compile_swap( compiler, px );
        /* ..., new_array, array_last_ptr == array */
        
        /* Will return here in the next loop iteration: */
        /* stack now: ..., new_array, array_current_ptr == array */
        compiler_push_current_address( compiler, px );

        /* Store the current array element into the loop variable: */
        /* stack now: ..., new_array, array_current_ptr */
        compiler_compile_dup( compiler, px );
        compiler_make_stack_top_element_type( compiler );
        compiler_make_stack_top_addressof( compiler, px );

        DNODE *loop_counter_var = $4;
        TNODE *aggregate_expression_type = enode_type( compiler->e_stack );
        TNODE *element_type = 
            aggregate_expression_type ?
            tnode_element_type( aggregate_expression_type ) : NULL;

        if( aggregate_expression_type &&
            tnode_kind( aggregate_expression_type ) == TK_ARRAY &&
            element_type &&
            tnode_kind( element_type ) != TK_PLACEHOLDER ) {
            compiler_compile_ldi( compiler, px );
        } else {
            compiler_emit( compiler, px, "\tc\n", GLDI );
            compiler_stack_top_dereference( compiler );
        }
        compiler_compile_variable_initialisation
            ( compiler, loop_counter_var, px );
        
        compiler_emit( compiler, px, "\n" );
        /* ..., new_array, array_last_ptr */

        compiler_merge_top_thrcodes( compiler, px );
        /* ..., new_array, array_last_ptr, expression */

        /* Store a new array element: */
        compiler_compile_peek( compiler, 3, px );
        compiler_make_stack_top_element_type( compiler );
        compiler_make_stack_top_addressof( compiler, px );
        compiler_compile_swap( compiler, px );
        compiler_compile_sti( compiler, px );
        /* ..., new_array, array_last_ptr */
        /* Advance the target array pointer: */
        compiler_compile_swap( compiler, px );
        /* ..., lvariable_address, array_last_ptr, new_array */
        compiler_emit( compiler, px, "\tcIc\n", LDC, 1, INDEX );
        compiler_compile_swap( compiler, px );
        /* ..., new_array, array_last_ptr */

        /* Finish the comprehension 'for' loop: */
        // compiler_fixup_here( compiler );
        compiler_fixup_op_continue( compiler, px );
	compiler_compile_next( compiler, compiler_pop_offset( compiler, px ),
                               px );
        compiler_fixup_op_break( compiler, px );
        compiler_pop_loop( compiler );
        compiler_end_subscope( compiler, px );
        compiler_emit( compiler, px, "\tc\n", ZEROOFFSET );
    }

/*
  | '[' expression ':' labeled_for variable_declaration_keyword for_variable_declaration _IN
     expression ':' expression ']'
*/
  ;

struct_expression
  : opt_null_type_designator _STRUCT type_identifier
     {
	 compiler_compile_alloc( compiler, $3, px );
         compiler_push_initialised_ref_tables( compiler, px );
     }
    '{' field_initialiser_list opt_comma '}'
    {
        DNODE *field, *field_list;

        field_list = tnode_fields( $3 );
        foreach_dnode( field, field_list ) {
            TNODE *field_type = dnode_type( field );
            char * field_name = dnode_name( field );
            if( tnode_is_non_null_reference( field_type ) &&
                !vartab_lookup( compiler->initialised_references,
                                field_name )) {
                char *field_type_name = $3 ? tnode_name( $3 ) : NULL;
                if( field_type_name ) {
                    yyerrorf( "non-null field '%s' of type '%s' "
                              "is not initialised",
                              field_name, field_type_name );
                } else {
                    yyerrorf( "non-null field '%s' is not initialised",
                              field_name );
                }
            }
        }

        compiler_pop_initialised_ref_tables( compiler );
    }

  | _TYPE type_identifier _OF delimited_type_description
     {
	 TNODE *composite = new_tnode_derived( $2, px );
	 tnode_set_kind( composite, TK_COMPOSITE );
	 tnode_insert_element_type( composite, $4 );

	 compiler_compile_alloc( compiler, share_tnode( composite ), px );
         compiler_push_initialised_ref_tables( compiler, px );
     }
    '{' field_initialiser_list opt_comma '}'
    {
        DNODE *field, *field_list;

        field_list = tnode_fields( $2 );
        foreach_dnode( field, field_list ) {
            TNODE *field_type = dnode_type( field );
            char * field_name = dnode_name( field );
            if( tnode_is_non_null_reference( field_type ) &&
                !vartab_lookup( compiler->initialised_references,
                                field_name )) {
                char *field_type_name = $2 ? tnode_name( $2 ) : NULL;
                if( field_type_name ) {
                    yyerrorf( "non-null field '%s' of type '%s' "
                              "is not initialised",
                              field_name, field_type_name );
                } else {
                    yyerrorf( "non-null field '%s' is not initialised",
                              field_name );
                }
            }
        }

        compiler_pop_initialised_ref_tables( compiler );
    }

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
         TNODE *field_type;
	 DNODE *volatile shared_field = NULL;
         char *volatile field_identifier =
             obtain_string_from_strpool( compiler->strpool, $1 );

         cexception_t inner;
         cexception_guard( inner ) {
             compiler_compile_dup( compiler, &inner );
             field = compiler_make_stack_top_field_type( compiler,
                                                         field_identifier );
             field_type = field ? dnode_type( field ) : NULL;
             compiler_make_stack_top_addressof( compiler, &inner );

             if( !vartab_lookup( compiler->initialised_references,
                                 field_identifier ) &&
                 field_type && tnode_is_non_null_reference( field_type )) {
                 shared_field = share_dnode( field );
                 vartab_insert_named( compiler->initialised_references,
                                      &shared_field, &inner );
             }

             if( field && dnode_offset( field ) != 0 ) {
                 ssize_t field_offset = dnode_offset( field );
                 compiler_emit( compiler, &inner, "\tce\n", OFFSET,
                                &field_offset );
             }
         }
         cexception_catch {
             freex( field_identifier );
             delete_dnode( shared_field );
             cexception_reraise( inner, px );
         }
         freex( field_identifier );
     }
    field_initialiser_separator expression
     {
	 compiler_compile_sti( compiler, px );
     }
  ;

arithmetic_expression
  : expression '+' expression
      {
       compiler_compile_binop( compiler, "+", px );
      }
  | expression '-' expression
      {
       compiler_compile_binop( compiler, "-", px );
      }
  | expression '*' expression
      {
       compiler_compile_binop( compiler, "*", px );
      }
  | expression '/' expression
      {
       compiler_compile_binop( compiler, "/", px );
      }
  | expression '&' expression
      {
       compiler_compile_binop( compiler, "&", px );
      }
  | expression '|' expression
      {
       compiler_compile_binop( compiler, "|", px );
      }
  | expression __RIGHT_TO_LEFT expression /* << */
      {
       compiler_compile_binop( compiler, "shl", px );
      }
  | expression __LEFT_TO_RIGHT expression /* >> */
      {
       compiler_compile_binop( compiler, "shr", px );
      }
  | expression _SHL expression
      {
       compiler_compile_binop( compiler, "shl", px );
      }
  | expression _SHR expression
      {
       compiler_compile_binop( compiler, "shr", px );
      }
  | expression '^' expression
      {
       compiler_compile_binop( compiler, "^", px );
      }
  | expression '%' expression
      {
       compiler_compile_binop( compiler, "%", px );
      }
  | expression __STAR_STAR expression
      {
       compiler_compile_binop( compiler, "**", px );
      }
  | expression '_' expression
      {
       compiler_compile_binop( compiler, "_", px );
      }

  | '+' expression %prec __UNARY
      {
       compiler_compile_unop( compiler, "+", px );
      }
  | '-' expression %prec __UNARY
      {
       compiler_compile_unop( compiler, "-", px );
      }
  | '~' expression %prec __UNARY
      {
       compiler_compile_unop( compiler, "~", px );
      }

  | expression __DOUBLE_PERCENT expression
      {
       compiler_compile_binop( compiler, "%%", px );
      }

  | __DOUBLE_PERCENT expression %prec __UNARY
      {
       compiler_compile_unop( compiler, "%%", px );
      }

/*
  | '<' __IDENTIFIER '>' expression %prec __UNARY
      {
       compiler_compile_named_type_conversion( compiler, /*target_name* /$2, px );
      }
*/

  | expression '@' __IDENTIFIER
      {
          char *target_name =
              obtain_string_from_strpool( compiler->strpool, $3 );
          compiler_compile_named_type_conversion( compiler, target_name, px );
          freex( target_name );
      }

  | expression '@' module_list __COLON_COLON __IDENTIFIER
      {
          DNODE *module = $3;
          char *target_name =
              obtain_string_from_strpool( compiler->strpool, $5 );
          TNODE *target_type = NULL;

          if( module ) {
              target_type = dnode_typetab_lookup_type( module, target_name );
          }

          compiler_compile_type_conversion( compiler, target_type, 
                                            target_name, px );
          freex( target_name );
      }

  | expression '@' '(' var_type_description ')'
      {
       compiler_compile_named_type_conversion( compiler, NULL, px );
      }

  | expression '?'
      {
        compiler_push_relative_fixup( compiler, px );
	compiler_compile_jz( compiler, 0, px );
      }
    expression ':'
      {
	ssize_t zero = 0;
        compiler_push_relative_fixup( compiler, px );
        compiler_emit( compiler, px, "\tce\n", JMP, &zero );
        compiler_swap_fixups( compiler );
        compiler_fixup_here( compiler );
      }
    expression
      {
	compiler_check_top_2_expressions_and_drop( compiler, "?:", px );
        compiler_fixup_here( compiler );
      }
/*
  | expression _AS __IDENTIFIER
*/
  | '(' arithmetic_expression ')'
  | '(' simple_expression ')'
  | '(' function_call ')'

  | '@' expression  %prec __UNARY
      {
       compiler_compile_unop( compiler, "@", px );
      }

  | ':' expression  %prec __UNARY
      {
       compiler_compile_unop( compiler, "@", px );
      }

  | __COLON_COLON expression  %prec __UNARY
      {
       compiler_compile_unop( compiler, "::", px );
      }

  | '_' expression  %prec __UNARY
      {
       compiler_compile_unop( compiler, "@", px );
      }

  | __QQ expression  %prec __UNARY
  {
      ENODE *top = compiler->e_stack;
      TNODE *top_type = top ? enode_type( top ) : NULL;

      if( top && top_type &&
          tnode_is_reference( top_type ) &&
          !tnode_is_non_null_reference( top_type )) {
          TNODE *converted = copy_unnamed_tnode( top_type, px );
          tnode_set_flags( converted, TF_NON_NULL );
          enode_replace_type( top, converted );
          /* top_type no longer valid here! */
          compiler_emit( compiler, px, "\tc\n", CHECKREF );
      }
  }

  ;

boolean_expression
  : expression '<' expression
      {
       compiler_compile_binop( compiler, "<", px );
      }
  | expression '>' expression
      {
       compiler_compile_binop( compiler, ">", px );
      }
  | expression __LE expression
      {
       compiler_compile_binop( compiler, "<=", px );
      }
  | expression __GE expression
      {
       compiler_compile_binop( compiler, ">=", px );
      }
  | expression __EQ expression
      {
       compiler_compile_binop( compiler, "==", px );
      }
  | expression __NE expression
      {
       compiler_compile_binop( compiler, "!=", px );
      }
  | expression _AND
      {
	compiler_compile_dup( compiler, px );
        compiler_push_relative_fixup( compiler, px );
	compiler_compile_jz( compiler, 0, px );
	compiler_duplicate_top_expression( compiler, px );
	compiler_compile_drop( compiler, px );
      }
    expression
      {
	compiler_check_top_2_expressions_and_drop( compiler, "and", px );
        compiler_fixup_here( compiler );
      }
  | expression _OR
      {
	compiler_compile_dup( compiler, px );
        compiler_push_relative_fixup( compiler, px );
	compiler_compile_jnz( compiler, 0, px );
	compiler_duplicate_top_expression( compiler, px );
	compiler_compile_drop( compiler, px );
      }
    expression
      {
	compiler_check_top_2_expressions_and_drop( compiler, "or", px );
	compiler_fixup_here( compiler );
      }
  | '!' expression %prec __UNARY
      {
       compiler_compile_unop( compiler, "!", px );
      }

  | '(' boolean_expression ')'
  ;

opt_dot_name
  : '.' __IDENTIFIER
  { $$ = $2; }
  | /* empty */
  { $$ = strpool_add_string( compiler->strpool, "", px ); }
;

generator_new
  : _NEW compact_type_description
      {
          TNODE *constructor_tnode;
          DNODE *constructor_dnode;

          compiler_check_type_contains_non_null_ref( $2 );
          /* The share_tnode($2) is not needed here, since the
             'compact_type_description' rule already returnes an
             allocated or shared TNODE: */
          compiler_compile_alloc( compiler, $2, px );

          constructor_dnode = $2 ? tnode_default_constructor( $2 ) : NULL;

          if( constructor_dnode ) {
              /* --- function (constructor) call generation starts here: */

              compiler_push_current_interface_nr( compiler, px );
              compiler_push_current_call( compiler, px );

              compiler->current_interface_nr = 0;

              constructor_tnode = constructor_dnode ?
                  dnode_type( constructor_dnode ) : NULL;

              compiler->current_call = share_dnode( constructor_dnode );
          
              compiler->current_arg = constructor_tnode ?
                  dnode_next( tnode_args( constructor_tnode )) :
                  NULL;

              compiler_compile_dup( compiler, px );
              compiler_push_guarding_arg( compiler, px );
              compiler_swap_top_expressions( compiler );
              
              int nretvals;
              char *constructor_name = constructor_tnode ?
                  tnode_name( constructor_tnode ) : NULL;

              nretvals = compiler_compile_multivalue_function_call( compiler, px );

              if( nretvals > 0 ) {
                  yyerrorf( "constructor '%s()' should not return a value",
                            constructor_name ? constructor_name : "???" );
              }
          }
      }

  | _NEW type_identifier opt_dot_name
      {
	  DNODE *constructor_dnode;
          TNODE *constructor_tnode;
          TNODE *type_tnode = $2;
          char  *constructor_name =
              obtain_string_from_strpool( compiler->strpool, $3 );

          compiler_check_type_contains_non_null_ref( type_tnode );
          compiler_compile_alloc( compiler, type_tnode, px );
          // compiler_compile_alloc( compiler, &type_tnode, px );

          /* --- function call generation starts here: */

          compiler_push_current_interface_nr( compiler, px );
          compiler_push_current_call( compiler, px );

          compiler->current_interface_nr = 0;

          constructor_dnode = type_tnode ?
              tnode_lookup_constructor( type_tnode, constructor_name ) : NULL;

          constructor_tnode = constructor_dnode ?
              dnode_type( constructor_dnode ) : NULL;

          compiler->current_call = share_dnode( constructor_dnode );

          compiler->current_arg = constructor_tnode ?
              dnode_next( tnode_args( constructor_tnode )) :
              NULL;

          compiler_compile_dup( compiler, px );
	  compiler_push_guarding_arg( compiler, px );
          compiler_swap_top_expressions( compiler );
          freex( constructor_name );
	}
    '(' opt_actual_argument_list ')'
        {
	    DNODE *constructor_dnode = compiler->current_call;
	    TNODE *constructor_tnode = constructor_dnode ?
                dnode_type( constructor_dnode ) : NULL;
            int nretvals;
            char *constructor_name = constructor_tnode ?
                tnode_name( constructor_tnode ) : NULL;

	    nretvals = compiler_compile_multivalue_function_call( compiler, px );

            if( nretvals > 0 ) {
                yyerrorf( "constructor '%s()' should not return a value",
                          constructor_name ? constructor_name : "???" );
            }
	}

  | _NEW compact_type_description '[' expression ']'
      {
          compiler_check_array_component_is_not_null( $2, compiler->e_stack );
          compiler_compile_array_alloc( compiler, $2, px );
      }
  | _NEW compact_type_description md_array_allocator '[' expression ']'
      {
          compiler_check_array_component_is_not_null( $2, compiler->e_stack  );
          compiler_compile_mdalloc( compiler, $2, $3, px );
      }
  | _NEW _ARRAY '[' expression ']' _OF var_type_description
      {
          compiler_check_array_component_is_not_null( $7, compiler->e_stack  );
          compiler_compile_array_alloc( compiler, $7, px );
      }
  | _NEW _ARRAY md_array_allocator '[' expression ']' _OF var_type_description
      {
          compiler_check_array_component_is_not_null( $8, compiler->e_stack  );
          compiler_compile_mdalloc( compiler, $8, $3, px );
      }
  | _NEW compact_type_description '[' expression ']' _OF var_type_description
      {
          compiler_check_array_component_is_not_null( $7, compiler->e_stack  );
          compiler_compile_composite_alloc( compiler, $2, $7, px );
      }
  | _NEW _BLOB '(' expression ')'
      {
	compiler_compile_blob_alloc( compiler, px );
      }
  | expression '*' _NEW '[' expression ']'
      {
          ENODE *top_expr = compiler->e_stack;
          ENODE *next_expr = top_expr ? enode_next( top_expr ) : NULL;
          TNODE *element_type =  next_expr ? enode_type( next_expr ) : NULL;
          compiler_compile_array_alloc( compiler, element_type, px );
          compiler_emit( compiler, px, "\tc\n", FILLARRAY );
          compiler_swap_top_expressions( compiler );
          compiler_drop_top_expression( compiler );
      }
  | expression '*' _NEW md_array_allocator '[' expression ']'
      {
          ssize_t level = $4;
          ENODE *top_expr = compiler->e_stack;
          ENODE *next_expr = top_expr ? enode_next( top_expr ) : NULL;
          ENODE *next2_expr = next_expr ? enode_next( next_expr ) : NULL;
          TNODE *element_type =  next_expr ? enode_type( next2_expr ) : NULL;
          compiler_compile_mdalloc( compiler, element_type, level, px );
          compiler_emit( compiler, px, "\tce\n", FILLMDARRAY, &level );
          compiler_swap_top_expressions( compiler );
          compiler_drop_top_expression( compiler );
      }
  ;

md_array_allocator
  : '[' expression ']'
      {
	int level = 0;
	compiler_compile_mdalloc( compiler, NULL, level, px );
	$$ = level + 1;
      }
  | md_array_allocator '[' expression ']'
      {
	int level = $1;
	compiler_compile_mdalloc( compiler, NULL, level, px );
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
      { compiler_compile_load_variable_address( compiler, $1, px ); }
  | lvalue
  ;

variable
  : variable_access_identifier
      {
	  DNODE *variable = $1;
	  TNODE *variable_type = variable ? dnode_type( variable ) : NULL; 

	  if( variable_type && tnode_kind( variable_type ) == TK_FUNCTION ) {
              if( variable && dnode_offset( variable ) == 0 ) {
                  thrcode_push_forward_function
                      ( compiler->thrcode, dnode_name( variable ),
                        thrcode_length( compiler->thrcode ) + 1, px );
              }
	      compiler_compile_load_function_address( compiler, variable, px );
	  } else {
	      compiler_compile_load_variable_value( compiler, variable, px );
	  }
      }
  ;

index_expression
  : expression
    { $$ = 1; }
  
  | expression __DOT_DOT expression
    { $$ = 2; }
  
  | expression ':' expression
    { $$ = 2; }
  
  | expression __DOT_DOT 
    { $$ = -1; }
  
  | expression ':'
    { $$ = -1; }
  
  | expression __THREE_DOTS 
    { $$ = -1; }
  
  | /* empty */
    { $$ = 0; }
;

variable_access_for_indexing
  : variable_access_identifier
      {
       if( compiler_dnode_is_reference( compiler, $1 )) {
           compiler_compile_load_variable_value( compiler, $1, px );
       } else {
           compiler_compile_load_variable_address( compiler, $1, px );
       }
       $$ = $1;
      }
  ;

lvalue_for_indexing
  : lvalue
      {
       if( compiler_stack_top_base_is_reference( compiler )) {
	   compiler_compile_ldi( compiler, px );
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
	  if( compiler_stack_top_has_operator( compiler, operator_name, 2, px ) ||
 	      compiler_nth_stack_value_has_operator( compiler, 1,
						  operator_name, 2, px )) {
	      compiler_check_and_compile_top_2_operator( compiler,
						      operator_name, 2, px );
	  } else {
	      if( compiler_dnode_is_reference( compiler, var_dnode )) {
		  compiler_compile_indexing( compiler, 1, $3, px );
	      } else {
		  compiler_compile_indexing( compiler, 0, $3, px );
	      }
	      compiler_compile_ldi( compiler, px );
	  }
      }
  | lvalue_for_indexing '[' index_expression ']'
      {
	  ENODE *top_expr = compiler->e_stack;
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
	  if( compiler_stack_top_has_operator( compiler, operator_name, 2, px ) ||
 	      compiler_nth_stack_value_has_operator( compiler, 1,
                                                  operator_name, 2, px )) {
	      compiler_check_and_compile_top_2_operator( compiler, operator_name,
                                                      2, px );
	  } else {
	      if( compiler_stack_top_is_reference( compiler )) {
		  compiler_compile_indexing( compiler, 1, $3, px );
	      } else {
		  compiler_compile_indexing( compiler, 0, $3, px );
	      }
	      compiler_compile_ldi( compiler, px );
	  }
      }
  ;

indexed_lvalue
  : variable_access_for_indexing '[' index_expression ']'
      {
	  if( compiler_dnode_is_reference( compiler, $1 )) {
	      compiler_compile_indexing( compiler, 1, $3, px );
	  } else {
	      compiler_compile_indexing( compiler, 0, $3, px );
	  }
      }

  | lvalue_for_indexing '[' index_expression ']'
      {
	  if( compiler_stack_top_is_reference( compiler )) {
	      compiler_compile_indexing( compiler, 1, $3, px );
	  } else {
	      compiler_compile_indexing( compiler, 0, $3, px );
	  }
      }
  ;

field_access
  : variable_access_identifier '.' __IDENTIFIER
      {
       DNODE *field;
       char *field_name = obtain_string_from_strpool( compiler->strpool, $3 );

       if( compiler_dnode_is_reference( compiler, $1 )) {
	   compiler_compile_load_variable_value( compiler, $1, px );
       } else {
           compiler_compile_load_variable_address( compiler, $1, px );
       }
       field = compiler_make_stack_top_field_type( compiler, field_name );
       compiler_make_stack_top_addressof( compiler, px );
       if( field && dnode_offset( field ) != 0 ) {
	   ssize_t field_offset = dnode_offset( field );
	   compiler_emit( compiler, px, "\tce\n", OFFSET, &field_offset );
       }
       freex( field_name );
      }
  | lvalue '.' __IDENTIFIER
      {
       DNODE *field;
       char *field_name = obtain_string_from_strpool( compiler->strpool, $3 );

       if( compiler_stack_top_base_is_reference( compiler )) {
	   compiler_compile_ldi( compiler, px );
       }
       field = compiler_make_stack_top_field_type( compiler, field_name );
       compiler_make_stack_top_addressof( compiler, px );
       if( field && dnode_offset( field ) != 0 ) {
	   ssize_t field_offset = dnode_offset( field );
	   compiler_emit( compiler, px, "\tce\n", OFFSET, &field_offset );
       }
       freex( field_name );
      }
  ;

assignment_expression
  : lvalue '=' expression
      {
       compiler_compile_swap( compiler, px );
       compiler_compile_over( compiler, px );
       compiler_compile_sti( compiler, px );
      }

  | variable_access_identifier '=' expression
      {
       compiler_compile_dup( compiler, px );
       compiler_compile_store_variable( compiler, $1, px );
      }

  | '(' assignment_expression ')'
  ;

constant
  : __INTEGER_CONST
      {
          char *int_text = obtain_string_from_strpool( compiler->strpool, $1 );
          compiler_compile_constant( compiler, TS_INTEGER_SUFFIX,
                                     NULL, NULL, "integer", int_text, px );
          freex( int_text );
      }
  | __INTEGER_CONST __IDENTIFIER
      {
          char *int_text = obtain_string_from_strpool( compiler->strpool, $1 );
          char *ident = obtain_string_from_strpool( compiler->strpool, $2 );
          compiler_compile_constant( compiler, TS_INTEGER_SUFFIX,
                                     NULL, ident, "integer", int_text, px );
          freex( int_text );
          freex( ident );
      }
  | __INTEGER_CONST module_list __COLON_COLON __IDENTIFIER
      {
          char *int_text = obtain_string_from_strpool( compiler->strpool, $1 );
          char *ident = obtain_string_from_strpool( compiler->strpool, $4 );
          compiler_compile_constant( compiler, TS_INTEGER_SUFFIX,
                                     $2, ident, "integer", int_text, px );
          freex( int_text );
          freex( ident );
      }
  | __REAL_CONST
      {
          char *real = obtain_string_from_strpool( compiler->strpool, $1 );
          compiler_compile_constant( compiler, TS_FLOAT_SUFFIX,
                                     NULL, NULL, "real", real, px );
          freex( real );
      }
  | __REAL_CONST __IDENTIFIER
      {
          char *real = obtain_string_from_strpool( compiler->strpool, $1 );
          char *ident = obtain_string_from_strpool( compiler->strpool, $2 );
          compiler_compile_constant( compiler, TS_FLOAT_SUFFIX,
                                  NULL, ident, "real", real, px );
          freex( real );
          freex( ident );
      }
  | __REAL_CONST module_list __COLON_COLON __IDENTIFIER
      {
          char *real = obtain_string_from_strpool( compiler->strpool, $1 );
          char *ident = obtain_string_from_strpool( compiler->strpool, $4 );
          compiler_compile_constant( compiler, TS_FLOAT_SUFFIX,
                                     $2, ident, "real", real, px );
          freex( real );
          freex( ident );
      }
  | __STRING_CONST
      {
          char *str = obtain_string_from_strpool( compiler->strpool, $1 );
          compiler_compile_constant( compiler, TS_STRING_SUFFIX,
                                     NULL, NULL, "string", str, px );
          freex( str );
      }
  | __STRING_CONST __IDENTIFIER
      {
          char *str = obtain_string_from_strpool( compiler->strpool, $1 );
          char *ident = obtain_string_from_strpool( compiler->strpool, $2 );
          compiler_compile_constant( compiler, TS_STRING_SUFFIX,
                                     NULL, ident, "string", str, px );
          freex( str );
          freex( ident );
      }
  | __STRING_CONST module_list __COLON_COLON __IDENTIFIER
      {
          char *str = obtain_string_from_strpool( compiler->strpool, $1 );
          char *ident = obtain_string_from_strpool( compiler->strpool, $4 );
          compiler_compile_constant( compiler, TS_STRING_SUFFIX,
                                     $2, ident, "string", str, px );
          freex( str );
          freex( ident );
      }
  | __IDENTIFIER  __IDENTIFIER
      {
          char *value = obtain_string_from_strpool( compiler->strpool, $1 );
          char *tenum = obtain_string_from_strpool( compiler->strpool, $2 );
          compiler_compile_enumeration_constant( compiler, NULL,
                                                 value, tenum, px );
          freex( value );
          freex( tenum );
      }

  | __IDENTIFIER module_list __COLON_COLON __IDENTIFIER
      {
          char *value = obtain_string_from_strpool( compiler->strpool, $1 );
          char *tenum = obtain_string_from_strpool( compiler->strpool, $4 );
          compiler_compile_enumeration_constant( compiler, $2,
                                                 value, tenum, px );
          freex( value );
          freex( tenum );
      }

  | _CONST __IDENTIFIER
      {
          char *const_str = obtain_string_from_strpool( compiler->strpool, $2 );
          DNODE *const_dnode =
              compiler_lookup_constant( compiler, NULL, const_str, "constant" );

          if( const_dnode ) {
              char pad[80];

              snprintf( pad, sizeof(pad), "%ld",
                        (long)dnode_ssize_value( const_dnode ));
              compiler_compile_constant( compiler, TS_INTEGER_SUFFIX,
                                         NULL, NULL, "integer", pad, px );
          }
          freex( const_str );
      }

  | _CONST module_list __COLON_COLON __IDENTIFIER
      {
          char *ident = obtain_string_from_strpool( compiler->strpool, $4 );
          DNODE *const_dnode = compiler_lookup_constant( compiler, $2, ident,
                                                         "constant" );
          freex( ident );
          if( const_dnode ) {
              char pad[80];

              snprintf( pad, sizeof(pad), "%ld",
                        (long)dnode_ssize_value( const_dnode ));
              compiler_compile_constant( compiler, TS_INTEGER_SUFFIX,
                                         NULL, NULL, "integer", pad, px );
          }
      }

  | _CONST '(' constant_expression ')'
      {
	  compiler_compile_multitype_const_value( compiler, &$3, NULL, NULL, px );
      }

  | _CONST '(' constant_expression ')' __IDENTIFIER
      {
          char *ident = obtain_string_from_strpool( compiler->strpool, $5 );
	  compiler_compile_multitype_const_value( compiler, &$3, NULL,
                                                  ident, px );
          freex( ident );
      }

  | _CONST '(' constant_expression ')'
    module_list __COLON_COLON __IDENTIFIER
      {
          char *ident = obtain_string_from_strpool( compiler->strpool, $7 );
	  compiler_compile_multitype_const_value( compiler, &$3, $5,
                                                  ident, px );
          freex( ident );
      }

  ;

argument_list
  : argument
    { $$ = $1; }
  | argument_list ';' argument
    { $$ = dnode_append( $1, $3 ); }
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
  : opt_readonly identifier_list ':' var_type_description
    {
	$$ = dnode_list_append_type( $2, $4 );
	if( $1 ) {
	    dnode_list_set_flags( $2, DF_IS_READONLY );
	}
    }

  | opt_readonly identifier_list ':' var_type_description
        '=' constant_expression
    {
	DNODE *arg;

	$$ = dnode_list_append_type( $2, $4 );
	foreach_dnode( arg, $2 ) {
	    const_value_t val = make_zero_const_value();
	    const_value_copy( &val, &$6, px );
	    compiler_check_default_value_compatibility( arg, &val );
	    dnode_set_value( arg, &val );
	    dnode_set_flags( arg, DF_HAS_INITIALISER );
	    if( $1 ) {
		dnode_set_flags( arg, DF_IS_READONLY );
	    }
	}
    }

  | opt_readonly var_type_description uninitialised_var_declarator_list
      {
	$$ = dnode_list_append_type( $3, $2 );
	if( $1 ) {
	    dnode_list_set_flags( $3, DF_IS_READONLY );
	}
      }

  | opt_readonly var_type_description variable_declarator
        '=' constant_expression
      {
        $$ = dnode_list_append_type( $3, $2 );
	compiler_check_default_value_compatibility( $3, &$5 );
	dnode_set_value( $3, &$5 );
	dnode_set_flags( $3, DF_HAS_INITIALISER );
	if( $1 ) {
	    dnode_set_flags( $3, DF_IS_READONLY );
	}
      }

  | opt_readonly __IDENTIFIER
      {
          char *ident = obtain_string_from_strpool( compiler->strpool, $2 );
	  $$ = new_dnode_name( ident, px );
	  dnode_append_type( $$, new_tnode_ignored( px ));
	  if( $1 ) {
	      dnode_list_set_flags( $$, DF_IS_READONLY );
	  }
          freex( ident );
      }
  ;

function_or_operator_start
  :
        {
	  cexception_t inner;
	  DNODE *volatile funct = $<dnode>0;
          TNODE *fn_tnode = funct ? dnode_type( funct ) : NULL;
	  int is_bytecode = dnode_has_flags( funct, DF_BYTECODE );

          dlist_push_dnode( &compiler->current_function_stack,
                            &compiler->current_function, px );

	  compiler->current_function = funct;
	  dnode_reset_flags( funct, DF_FNPROTO );

          compiler_push_thrcode( compiler, px );

    	  cexception_guard( inner ) {
	      compiler_push_current_address( compiler, px );

	      if( !is_bytecode ) {
		  ssize_t zero = 0;
		  compiler_push_absolute_fixup( compiler, px );
		  compiler_emit( compiler, px, "\tce\n", ENTER, &zero );
	      }

              compiler_begin_scope( compiler, &inner );
	  }
	  cexception_catch {
	      delete_dnode( funct );
	      compiler->current_function =
                  dlist_pop_data( &compiler->current_function_stack );
	      cexception_reraise( inner, px );
	  }
	  if( !is_bytecode ) {
	      compiler_emit_function_arguments( funct, compiler, px );
	  }
          if( fn_tnode && tnode_kind( fn_tnode ) == TK_CLOSURE ) {
              tnode_drop_last_argument( fn_tnode );
          }
	}
;

function_or_operator_end
  :
        {
	  DNODE *funct = compiler->current_function;
          TNODE *funct_tnode = funct ? dnode_type( funct ) : NULL;
	  int is_bytecode = dnode_has_flags( funct, DF_BYTECODE );
          ssize_t function_entry_address = thrcode_length( compiler->function_thrcode );

	  if( !is_bytecode ) {
	      /* patch ENTER command: */
	      compiler_fixup( compiler, -compiler->local_offset );
	  }
          
          if( funct_tnode && tnode_kind( funct_tnode ) == TK_METHOD ) {
              dnode_set_ssize_value( funct, function_entry_address );
          } else {
              dnode_set_offset( funct, function_entry_address );
          }

	  compiler_get_inline_code( compiler, funct, px );

          if( funct_tnode && tnode_kind( funct_tnode ) == TK_DESTRUCTOR ) {
              DNODE *first_arg = tnode_args( funct_tnode ); /* The 'self' arg */
              TNODE *class_tnode = first_arg ? dnode_type( first_arg ) : NULL;
              TNODE *base_class =
                  class_tnode ? tnode_base_type( class_tnode ) : NULL;
              DNODE *base_destructor =
                  base_class ? tnode_destructor( base_class ) : NULL;
              if( base_destructor ) {
                  /* Generate code to pass control to the base
                     classe's destructor: */
                  ssize_t self_offset = dnode_offset( first_arg );
                  ssize_t destructor_offset =
                      dnode_offset( base_destructor );
                  compiler_emit( compiler, px, "\tce\n", PLD, &self_offset );
                  compiler_emit( compiler, px, "\tce\n", CALL, &destructor_offset );
              }
          }

	  if( thrcode_last_opcode( compiler->thrcode ).fn != RET ) {
	      compiler_emit( compiler, px, "\tc\n", RET );
	  }

          compiler_merge_functions_and_top( compiler, px );
          if( !compiler->thrcode ) {
              compiler->thrcode = share_thrcode( compiler->main_thrcode );
          }
          compiler_fixup_function_calls( compiler->function_thrcode, funct );
          compiler_fixup_function_calls( compiler->main_thrcode, funct );
	  compiler_end_scope( compiler, px );
	  compiler->current_function = 
              dlist_pop_data( &compiler->current_function_stack );
	}
;

method_definition
  : method_header
    function_or_operator_start
    function_or_operator_body
    function_or_operator_end
  ;

constructor_definition
  : constructor_header
    function_or_operator_start
    opt_base_class_initialisation
    function_or_operator_body
    function_or_operator_end
  ;

destructor_definition
  : destructor_header
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
  | __THICK_ARROW
  {
      compiler_push_guarding_retval( compiler, px );
  }
  expression_list ';'
  {
      compiler_compile_return( compiler, $3, px );
  }
  | __THICK_ARROW
  {
      compiler_push_guarding_retval( compiler, px );
  }
  '{' expression_list '}'
  {
      compiler_compile_return( compiler, $4, px );
  }
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
      if( thrcode_debug_is_on()) {
	  const char *currentLine = compiler_flex_current_line();
	  const char *first_nonblank = currentLine;
	  while( isspace( *first_nonblank )) first_nonblank++;
	  if( *first_nonblank == '#' ) {
              thrcode_printf( compiler->function_thrcode, px,
                              "%s\n", currentLine );
	  } else {
              thrcode_printf( compiler->function_thrcode, px,
                              "#\n# %s\n#\n", currentLine );
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
    __IDENTIFIER '(' argument_list ')'
    opt_retval_description_list
        {
	  cexception_t inner;
	  DNODE *volatile funct = NULL;
	  int is_function = $2;
          char *volatile function_name =
              obtain_string_from_strpool( compiler->strpool, $3 );
          DNODE *volatile parameters = $5;
          DNODE *volatile retvals = $7;

    	  cexception_guard( inner ) {
	      $$ = funct = new_dnode_function( function_name, parameters,
                                               retvals, &inner );
	      parameters = NULL;
	      retvals = NULL;
	      dnode_set_flags( funct, DF_FNPROTO );
	      if( $1 & DF_BYTECODE )
	          dnode_set_flags( funct, DF_BYTECODE );
	      if( $1 & DF_INLINE )
	          dnode_set_flags( funct, DF_INLINE );
	      funct = $$ =
		  compiler_check_and_set_fn_proto( compiler, funct, px );
	      if( is_function ) {
		  compiler_set_function_arguments_readonly( dnode_type( funct ));
	      }
	  }
	  cexception_catch {
	      delete_dnode( parameters );
	      delete_dnode( retvals );
	      delete_dnode( funct );
	      $$ = NULL;
              freex( function_name );
	      cexception_reraise( inner, px );
	  }
          freex( function_name );
	}
  ;

opt_method_interface
  : '@' __IDENTIFIER
  {
      char *interface_name =
          obtain_string_from_strpool( compiler->strpool, $2 );
      $$ = compiler_lookup_tnode( compiler, /*module_name =*/ NULL,
                                  interface_name, "interface" );
      freex( interface_name );
  }
  | '@' module_list __COLON_COLON __IDENTIFIER
  {
      DNODE *module = $2;
      char *interface_name =
          obtain_string_from_strpool( compiler->strpool, $4 );
      $$ = compiler_lookup_tnode( compiler, module,
                                  interface_name, "interface" );
      freex( interface_name );
  }
  | /* empty */
  { $$ = NULL; }
;

method_header
  : opt_function_attributes function_code_start _METHOD
    __IDENTIFIER opt_method_interface '(' argument_list ')'
    opt_retval_description_list
        {
	  cexception_t inner;
	  DNODE *volatile funct = NULL;
          DNODE *volatile self_dnode = NULL;
          TNODE *current_class = compiler->current_type;;
          char *method_name =
              obtain_string_from_strpool( compiler->strpool, $4 );
          TNODE *interface_type = $5;
          DNODE *implements_method = NULL;
          DNODE *volatile parameter_list = $7;
          DNODE *volatile return_values = $9;
	  int is_function = 0, class_has_interface = 1;

          assert( current_class );
    	  cexception_guard( inner ) {
              self_dnode = new_dnode_name( "self", &inner );

              dnode_insert_type( self_dnode, share_tnode( current_class ));

              parameter_list = dnode_append( self_dnode, parameter_list );
              self_dnode = NULL;

              if( interface_type ) {
                  char * interface_name = tnode_name( interface_type );
                  assert( interface_name );
                  if( current_class ) {
                      class_has_interface =
                          tnode_lookup_interface
                          ( current_class, interface_name ) != NULL;
                      if( !class_has_interface ) {
                          char *class_name = tnode_name( current_class );
                          if( class_name ) {
                              yyerrorf( "class '%s' does not implement "
                                        "interface '%s'",
                                        class_name, interface_name );
                          } else {
                              yyerrorf( "current class does not implement "
                                        "interface '%s'",
                                        interface_name );
                          }
                      }
                  }

                  implements_method =
                      tnode_lookup_method_prototype( interface_type,
                                                     method_name );
                  if( !implements_method ) {
                      if( interface_name ) {
                          yyerrorf( "interface '%s' does not implement method "
                                    "'%s'", interface_name, method_name );
                      } else {
                          yyerrorf( "this interface does not declare method "
                                    "'%s'", method_name );
                      }
                  }
              }

              if( interface_type ) {
                  cexception_t inner2;
                  char *interface_name = tnode_name( interface_type );
                  char *volatile full_method_name = NULL;
                  ssize_t length;
                  length = (interface_name ? strlen( interface_name ) : 0)
                      + (method_name ? strlen( method_name ) : 0) + 2;

                  cexception_guard( inner2 ) {
                      full_method_name = mallocx( length, &inner2 );

                      snprintf( full_method_name, length, "%s@%s",
                                method_name ? method_name : "",
                                interface_name ? interface_name : ""
                                );

                      funct = new_dnode_method( full_method_name, parameter_list,
                                                return_values, &inner2 );
                      freex( full_method_name );
                  }
                  cexception_catch {
                      freex( full_method_name );
                      cexception_reraise( inner2, &inner );
                  }
              } else {
                  funct = new_dnode_method( method_name, parameter_list,
                                            return_values, &inner );
              }

              $$ = funct;

              if( implements_method ) {
                  TNODE *method_type = dnode_type( funct );
                  TNODE *implements_type = dnode_type( implements_method );
                  char msg[300];

                  if( !tnode_function_prototypes_match_msg
                      ( implements_type, method_type, msg, sizeof( msg ))) {
                      if( class_has_interface ) {
                          yyerrorf( "method %s() does not match "
                                    "method %s it should implement"
                                    " - %s",
                                    method_name,
                                    dnode_name( implements_method ),
                                    msg );
                      }
                  } else {
                      ssize_t method_offset = dnode_offset( implements_method );
                      TNODE *interface_method_type =
                          dnode_type( implements_method );
                      TNODE *implemented_method_type = dnode_type( funct );
                      ssize_t interface_nr = interface_method_type ?
                          tnode_interface_number( interface_method_type ) : -1;

                      dnode_set_offset( funct, method_offset );
                      tnode_set_interface_nr( implemented_method_type,
                                              interface_nr );
#if 0
                      printf( ">>> interface = %d, method = %d ('%s')\n",
                              interface_nr, method_offset, method_name );
#endif
                  }
              }

	      parameter_list = NULL;
	      return_values = NULL;
	      dnode_set_flags( funct, DF_FNPROTO );
	      if( $1 & DF_BYTECODE )
	          dnode_set_flags( funct, DF_BYTECODE );
	      if( $1 & DF_INLINE )
	          dnode_set_flags( funct, DF_INLINE );
              dnode_set_scope( funct, compiler_current_scope( compiler ));
	      funct = $$ =
		  compiler_check_and_set_fn_proto( compiler, funct, px );
	      share_dnode( funct );
              tnode_insert_single_method( current_class, share_dnode( funct ));
	      if( is_function ) {
		  compiler_set_function_arguments_readonly( dnode_type( funct ));
	      }
	  }
	  cexception_catch {
	      delete_dnode( parameter_list );
	      delete_dnode( return_values );
	      delete_dnode( funct );
              delete_dnode( self_dnode );
	      $$ = NULL;
              freex( method_name );
	      cexception_reraise( inner, px );
	  }
          freex( method_name );
	}
  ;

opt_semicolon
  : ';'
  | /* empty */
  ;

opt_base_class_initialisation
: __IDENTIFIER 
    {
        TNODE *type_tnode = compiler->current_type;
        TNODE *base_type_tnode =
            type_tnode ? tnode_base_type( type_tnode ) : NULL;
        DNODE *constructor_dnode;
        TNODE *constructor_tnode;
        DNODE *self_dnode;

        assert( type_tnode );
        compiler_emit( compiler, px, "T\n", "# Initialising base class:" );

        compiler_push_current_interface_nr( compiler, px );
        compiler_push_current_call( compiler, px );

        compiler->current_interface_nr = 0;

        constructor_dnode = base_type_tnode ?
            tnode_default_constructor( base_type_tnode ) : NULL;

        constructor_tnode = constructor_dnode ?
            dnode_type( constructor_dnode ) : NULL;

        compiler->current_call = share_dnode( constructor_dnode );
          
        compiler->current_arg = constructor_tnode ?
            dnode_next( tnode_args( constructor_tnode )) :
            NULL;

        self_dnode = compiler_lookup_dnode( compiler, NULL, "self", "variable" );
        compiler_push_guarding_arg( compiler, px );
        compiler_compile_load_variable_value( compiler, self_dnode, px );
    }
'(' opt_actual_argument_list ')' opt_semicolon
    {
        ssize_t nretval;
        nretval = compiler_compile_multivalue_function_call( compiler, px );
        assert( nretval == 0 );
    }
| /* empty */
;

constructor_header
  : opt_function_attributes function_code_start _CONSTRUCTOR
    opt_identifier '(' argument_list ')'
        {
	  cexception_t inner;
	  DNODE *volatile funct = NULL;
          DNODE *volatile self_dnode = NULL;
          
          int function_attributes = $1;
          char *constructor_name =
              obtain_string_from_strpool( compiler->strpool, $4 );
          DNODE *parameter_list = $6;

    	  cexception_guard( inner ) {
              TNODE *class_tnode = compiler->current_type;

              // share_tnode( class_tnode );

              assert( class_tnode );
              self_dnode = new_dnode_name( "self", &inner );
              dnode_insert_type( self_dnode, share_tnode( class_tnode ));

              parameter_list = dnode_append( self_dnode, parameter_list );
              self_dnode = NULL;

	      $$ = funct = new_dnode_constructor( constructor_name,
                                                  parameter_list,
                                                  /* return_dnode = */ NULL,
                                                  &inner );
	      parameter_list = NULL;

              dnode_set_scope( funct, compiler_current_scope( compiler ));

#if 0
              tnode_insert_constructor( class_tnode, share_dnode( funct ));
#endif

	      dnode_set_flags( funct, DF_FNPROTO );
	      if( function_attributes & DF_BYTECODE )
	          dnode_set_flags( funct, DF_BYTECODE );
	      if( function_attributes & DF_INLINE )
	          dnode_set_flags( funct, DF_INLINE );
#if 1
	      funct = $$ =
		  compiler_check_and_set_constructor( class_tnode, funct, px );
              share_dnode( funct );
#else
              $$ = funct;
#endif

              /* Constructors are always functions (?): */
              /* compiler_set_function_arguments_readonly( dnode_type( funct )); */
	  }
	  cexception_catch {
	      delete_dnode( parameter_list );
	      delete_dnode( funct );
	      $$ = NULL;
              freex( constructor_name );
              cexception_reraise( inner, px );
	  }
          freex( constructor_name );
	}
  ;

destructor_header
  : opt_function_attributes function_code_start _DESTRUCTOR opt_identifier
        {
	  cexception_t inner;
	  DNODE *volatile funct = NULL;
          DNODE *volatile self_dnode = NULL;
          
          int function_attributes = $1;
          char *destructor_name =
              obtain_string_from_strpool( compiler->strpool, $4 );

    	  cexception_guard( inner ) {
              TNODE *class_tnode = compiler->current_type;
              char *class_name = tnode_name( class_tnode );

              assert( class_tnode );
              self_dnode = new_dnode_name( "self", &inner );
              dnode_insert_type( self_dnode, share_tnode( class_tnode ));

              if( destructor_name && destructor_name[0] != '\0' ) {
                  if( class_name &&
                      strcmp( class_name, destructor_name ) != 0 ) {
                      yyerrorf( "destructor name '%s' does not match "
                                "class name '%s'", destructor_name,
                                class_name );
                  }
              }

              if( !class_name || class_name[0] == '\0' ) {
                  if( destructor_name && destructor_name[0] != '\0' ) {
                      yyerrorf( "destructors of anonymous classes "
                                "should be anonymous" );
                  }
              }

	      $$ = funct = new_dnode_destructor( destructor_name,
                                                 self_dnode, &inner );

              self_dnode = NULL;

              dnode_set_scope( funct, compiler_current_scope( compiler ));

              tnode_insert_destructor( class_tnode, share_dnode( funct ));

	      dnode_set_flags( funct, DF_FNPROTO );
	      if( function_attributes & DF_BYTECODE )
	          dnode_set_flags( funct, DF_BYTECODE );
	      if( function_attributes & DF_INLINE )
	          dnode_set_flags( funct, DF_INLINE );
	  }
	  cexception_catch {
	      delete_dnode( self_dnode );
	      delete_dnode( funct );
	      $$ = NULL;
              freex( destructor_name );
	      cexception_reraise( inner, px );
	  }
          freex( destructor_name );
	}
  ;

operator_keyword
: function_code_start _OPERATOR
;

operator_header
  : opt_function_attributes operator_keyword
    __STRING_CONST '(' argument_list ')'
    opt_retval_description_list
        {
	  cexception_t inner;
	  DNODE *volatile funct = NULL;
          char *operator_name =
              obtain_string_from_strpool( compiler->strpool, $3 );
          DNODE *volatile arguments = $5;
          DNODE *volatile retvals = $7;

    	  cexception_guard( inner ) {
	      $$ = funct = new_dnode_operator( operator_name, 
                                               arguments, retvals, &inner );
	      arguments = NULL;
	      retvals = NULL;
	      if( $1 & DF_BYTECODE )
		dnode_set_flags( funct, DF_BYTECODE );
	      if( $1 & DF_INLINE )
	          dnode_set_flags( funct, DF_INLINE );
	      $$ = funct;
              compiler_set_function_arguments_readonly( dnode_type( funct ));
	  }
	  cexception_catch {
	      delete_dnode( arguments );
	      delete_dnode( retvals );
	      delete_dnode( funct );
              freex( operator_name );
	      $$ = NULL;
	      cexception_reraise( inner, px );
	  }
          freex( operator_name );
	}
  ;

function_prototype
  : function_header
  | _FORWARD function_header
  ;

/*---------------------------------------------------------------------------*/

constant_declaration
  : _CONST __IDENTIFIER '=' constant_expression
    {
        char *volatile ident =
            obtain_string_from_strpool( compiler->strpool, $2 );
        DNODE *volatile const_dnode = new_dnode_constant( ident, &$4, px );

        cexception_t inner;
        cexception_guard( inner ) {
            compiler_consttab_insert_consts( compiler, &const_dnode, &inner );
        }
        cexception_catch {
            freex( ident );
            delete_dnode( const_dnode );
            cexception_reraise( inner, px );
        }
        freex( ident );
    }
;

constant_integer_expression
  : constant_expression
    {
	if( const_value_type( &$1 ) == VT_INTMAX ) {
	    $$ = const_value_integer( &$1 );
	} else {
	    yyerrorf( "constant integer value required" );
	}
    }
;

field_designator
  : __IDENTIFIER '.' __IDENTIFIER
    {
        char *structure = obtain_string_from_strpool( compiler->strpool, $1 );
        char *field = obtain_string_from_strpool( compiler->strpool, $3 );
	$$ = compiler_lookup_type_field( compiler, NULL, structure, field );
        freex( structure );
        freex( field );
    }
  | '(' type_identifier _OF delimited_type_description ')' '.' __IDENTIFIER
    {
        char *ident = obtain_string_from_strpool( compiler->strpool, $7 );
        TNODE *composite = $2;
        composite = new_tnode_derived( composite, px );
        tnode_set_kind( composite, TK_COMPOSITE );
        tnode_insert_element_type( composite, $4 );
        
	$$ = compiler_lookup_tnode_field( compiler, composite, ident );

        freex( ident );
    }
  | module_list __COLON_COLON __IDENTIFIER  '.' __IDENTIFIER
    {
        char *structure = obtain_string_from_strpool( compiler->strpool, $3 );
        char *field = obtain_string_from_strpool( compiler->strpool, $5 );
	$$ = compiler_lookup_type_field( compiler, $1, structure, field );
        freex( structure );
        freex( field );
    }
  | field_designator '.' __IDENTIFIER
    {
        char *subfield = obtain_string_from_strpool( compiler->strpool, $3 );
	DNODE *field = $1;
	TNODE *tnode = field ? dnode_type( field ) : NULL;
	$$ = tnode ? tnode_lookup_field( tnode, subfield ) : NULL;
        freex( subfield );
    }
;

constant_expression
  : _NULL
      { $$ = make_const_value( px, VT_NULL ); }

  | __INTEGER_CONST
      {
          intmax_t value;
          char *int_str = obtain_string_from_strpool( compiler->strpool, $1 );

          errno = 0;
          value = strtoll( int_str, NULL, 0 );
          if( errno ) {
              int errnoll = errno;
              errno = 0;
              value = strtoull( int_str, NULL, 0 );
              if( errno ) {
                  char *message = strerror(errno);
                  yyerrorf( "when converting integer constant '%s' - %c%s",
                            int_str, tolower(message[0]),
                            *message == '\0' ? "" : message+1 );
              } else {
                  if( value == LLONG_MIN ) {
                      fprintf( stderr, "%s: WARNING, value '%s' converts to "
                               "a negative number\n", progname, int_str );
                  } else {
                      char *message = strerror(errnoll);
                      yyerrorf( "when converting signed integer constant "
                                "'%s' - %c%s", int_str, tolower(message[0]),
                                *message == '\0' ? "" : message+1 );
                  }
              }
          }
	  $$ = make_const_value( px, VT_INTMAX, value );
          freex( int_str );
      }

  | __REAL_CONST
      {
          char *real = obtain_string_from_strpool( compiler->strpool, $1 );
	  $$ = make_const_value( px, VT_FLOAT, atof( real ));
          freex( real );
      }

  | __STRING_CONST
      {
          char *str = obtain_string_from_strpool( compiler->strpool, $1 );
	  $$ = make_const_value( px, VT_STRING, str );
          freex( str );
      }

  | __IDENTIFIER __IDENTIFIER
      {
          char *enum_str = obtain_string_from_strpool( compiler->strpool, $1 );
          char *enum_typ = obtain_string_from_strpool( compiler->strpool, $2 );
          
	  $$ = make_const_value( px, VT_ENUM, enum_str, enum_typ );

          freex( enum_str );
          freex( enum_typ );
      }

  | __IDENTIFIER
      {
          char *ident = obtain_string_from_strpool( compiler->strpool, $1 );
          DNODE *const_dnode = compiler_lookup_constant( compiler, NULL, ident,
                                                         "constant" );
          $$ = make_zero_const_value();
          if( const_dnode ) {
              const_value_copy( &$$, dnode_value( const_dnode ), px );
          } else {
              $$ = make_const_value( px, VT_INTMAX, (intmax_t)0 );
          }
          freex( ident );
      }

  | module_list __COLON_COLON __IDENTIFIER
      {
          char *ident = obtain_string_from_strpool( compiler->strpool, $3 );
          DNODE *const_dnode = compiler_lookup_constant( compiler, $1, ident,
                                                         "constant" );
          $$ = make_zero_const_value();
          if( const_dnode ) {
              const_value_copy( &$$, dnode_value( const_dnode ), px );
          } else {
              $$ = make_const_value( px, VT_INTMAX, (intmax_t)0 );
          }
          freex( ident );
      }

  | field_designator '.' __IDENTIFIER
      {
          char *ident = obtain_string_from_strpool( compiler->strpool, $3 );
	  $$ = compiler_get_dnode_compile_time_attribute( $1, ident, px );
          freex( ident );
      }

  | __IDENTIFIER '.' __IDENTIFIER
      {
          char *structure = obtain_string_from_strpool( compiler->strpool, $1 );
          char *field = obtain_string_from_strpool( compiler->strpool, $3 );
	  $$ = compiler_make_compile_time_value( compiler, NULL,
                                                 structure, field, px );
          freex( structure );
          freex( field );
      }

  | module_list __COLON_COLON __IDENTIFIER '.' __IDENTIFIER
      {
          char *structure = obtain_string_from_strpool( compiler->strpool, $3 );
          char *field = obtain_string_from_strpool( compiler->strpool, $5 );
	  $$ = compiler_make_compile_time_value( compiler, $1,
                                                 structure, field, px );
          freex( structure );
          freex( field );
      }

  | '.' __IDENTIFIER
      {
          char *ident = obtain_string_from_strpool( compiler->strpool, $2 );
	  $$ = compiler_make_compiler_attribute( ident, px );
          freex( ident );
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

static void compiler_compile_file( char *filename, cexception_t *ex )
{
    cexception_t inner;

    cexception_guard( inner ) {
        if( filename && !(strcmp( filename, "-" ) == 0) ) {
            yyin = fopenx( filename, "r", ex );
        } else {
            yyin = stdin;
        }
	if( yyparse() != 0 ) {
	    int errcount = compiler_yy_error_number();
	    cexception_raise( &inner, COMPILER_UNRECOVERABLE_ERROR,
			      cxprintf( "compiler could not recover "
					"from errors, quitting now\n"
					"%d error(s) detected\n",
					errcount ));
	} else {
	    int errcount = compiler_yy_error_number();
	    if( errcount != 0 ) {
	        cexception_raise( &inner, COMPILER_COMPILATION_ERROR,
				  cxprintf( "%d error(s) detected\n",
					    errcount ));
	    }
	}
    }
    cexception_catch {
        if( yyin && yyin != stdin )
            fclosex( yyin, ex );
        assert( !compiler->yyin || compiler->yyin == yyin );
        compiler->yyin = NULL;
        yyin = NULL;
        cexception_reraise( inner, ex );
    }
    if( yyin != stdin )
        fclosex( yyin, ex );
    assert( !compiler->yyin || compiler->yyin == yyin );
    compiler->yyin = NULL;
    yyin = NULL;
}

static void compiler_compile_string( char *program, cexception_t *ex )
{
    cexception_t inner;
    struct yy_buffer_state * volatile bstate = yy_scan_string( program );;
    
    cexception_guard( inner ) {
	if( yyparse() != 0 ) {
	    int errcount = compiler_yy_error_number();
	    cexception_raise( &inner, COMPILER_UNRECOVERABLE_ERROR,
			      cxprintf( "compiler could not recover "
					"from errors, quitting now\n"
					"%d error(s) detected\n",
					errcount ));
	} else {
	    int errcount = compiler_yy_error_number();
	    if( errcount != 0 ) {
	        cexception_raise( &inner, COMPILER_COMPILATION_ERROR,
				  cxprintf( "%d error(s) detected\n",
					    errcount ));
	    }
	}
    }
    cexception_catch {
        yy_delete_buffer( bstate );
	cexception_reraise( inner, ex );
    }
    yy_delete_buffer( bstate );
}

THRCODE *new_thrcode_from_file( char *filename, char **include_paths,
                                cexception_t *ex )
{
    THRCODE *volatile code = NULL;
    cexception_t inner;

    assert( !compiler );
    compiler = new_compiler( filename, include_paths, ex );

    cexception_guard( inner ) {
        compiler_compile_file( filename, &inner );

        thrcode_flush_lines( compiler->thrcode );
        code = share_thrcode( compiler->thrcode );
        thrcode_insert_static_data( code, compiler->static_data,
                                    compiler->static_data_size );
        compiler->static_data = NULL;
        delete_compiler( compiler );
        compiler = NULL;
    }
    cexception_catch {
        delete_compiler( compiler );
        compiler = NULL;
        delete_thrcode( code );
        cexception_reraise( inner, ex );
    }

    return code;
}

THRCODE *new_thrcode_from_string( char *program, char **include_paths,
                                  cexception_t *ex )
{
    THRCODE *volatile code = NULL;
    cexception_t inner;

    assert( !compiler );
    compiler = new_compiler( "-e ", include_paths, ex );

    cexception_guard( inner ) {
        compiler_compile_string( program, &inner );

        thrcode_flush_lines( compiler->thrcode );
        code = share_thrcode( compiler->thrcode );

        thrcode_insert_static_data( code, compiler->static_data,
                                    compiler->static_data_size );
        compiler->static_data = NULL;
        delete_compiler( compiler );
        compiler = NULL;
    }
    cexception_catch {
        delete_compiler( compiler );
        compiler = NULL;
        delete_thrcode( code );
        cexception_reraise( inner, ex );
    }

    return code;
}

STRPOOL *current_compiler_strpool( void )
{
    if( compiler ) {
        return compiler->strpool;
    } else {
        return NULL;
    }
}

void compiler_printf( cexception_t *ex, char *format, ... )
{
    cexception_t inner;
    va_list ap;

    va_start( ap, format );
    assert( format );
    assert( compiler );
    assert( compiler->thrcode );

    cexception_guard( inner ) {
	thrcode_printf_va( compiler->thrcode, &inner, format, ap );
    }
    cexception_catch {
	va_end( ap );
	cexception_reraise( inner, ex );
    }
    va_end( ap );
}

static int errcount = 0;

int compiler_yy_error_number( void )
{
    return errcount;
}

void compiler_yy_reset_error_count( void )
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
	    progname, compiler->filename,
	    compiler_flex_current_line_number(),
	    compiler_flex_current_position(),
	    message );
    fprintf(stderr, "%s\n", compiler_flex_current_line() );
    fprintf(stderr, "%*s\n", compiler_flex_current_position(), "^" );
    fflush(NULL);
    return 0;
}

int yywrap()
{
    if( compiler->include_files ) {
	compiler_close_include_file( compiler, px );
	return 0;
    } else {
	return 1;
    }
}

void compiler_yy_debug_on( void )
{
#ifdef YYDEBUG
    yydebug = 1;
#endif
}

void compiler_yy_debug_off( void )
{
#ifdef YYDEBUG
    yydebug = 0;
#endif
}

void compiler_memleak_debug_on( void )
{
    memleak_debug = 1;
}
