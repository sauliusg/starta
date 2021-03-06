/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#define _GNU_SOURCE
#include <pack.h>

/* uses: */
#include <string.h>
#include <ctype.h>
#include <run.h>
#include <assert.h>
#include <bcalloc.h> /* for bc_merror() */
#include <alloccell.h>

#define BC_CHECK_PTR( PTR, EXCEPTION )                    \
    if( !(PTR) ) { \
        bc_merror( EXCEPTION ); \
        return 0; \
    }

int pack_value( stackcell_t *stack_cell, char typechar, ssize_t size,
                ssize_t *offset, byte *blob,
                int (*pack)( stackcell_t *stack_cell, char typechar,
                             ssize_t size, ssize_t *offset, byte *blob ),
                cexception_t *ex
                )
{
    int retval;
    alloccell_t *blob_header = ((alloccell_t*)blob) - 1;

    assert( blob_header->magic == BC_MAGIC );

    if( blob_header->size < size + *offset ) {
	interpret_raise_exception_with_bcalloc_message
	    ( /* err_code = */ -1,
	      /* message = */
	      "attempting to pack values past the end of a blob",
	      /* module_id = */ 0,
	      /* exception_id = */ SL_EXCEPTION_BLOB_OVERFLOW,
	      ex );
	return 0;
    }

    retval = (*pack)( stack_cell, typechar, size, offset, blob );

    return retval;
}

int pack_array_values( byte *blob, stackcell_t *array,
                       char *description, ssize_t *offset,
                       int (*pack)( stackcell_t *stack_cell, 
                                    char typechar, ssize_t size, 
                                    ssize_t *offset, byte *blob ),
                       cexception_t *ex )
{
    alloccell_t *blob_header;
    int i;
    ssize_t size, length, count, start;
    char *count_str;
    char typechar;

    blob_header = ((alloccell_t*)blob) - 1;
    start = 0;
    while( *description ) {

	size = count = 0;
        typechar = description[0];
        if( isdigit( description[1] )) {
            if( description[0] != '\0' ) {
                size = strtol( description + 1, &count_str, 0 );
                if( count_str && count_str[0] && count_str[1] ) {
                    count = strtol( count_str + 1, &description, 0 );
                }
            }
        } else if( description[1] != '\0' ) {
            count = strtol( description + 2, NULL, 0 );
        }

	if( count <= 0 ) {
	    BC_CHECK_PTR( array, ex );
	    count = ((alloccell_t*)array)[-1].length - start;
	}

        if( count > 0 ) {
            if( size > 0 ) {
                if( blob_header->size < size * count + *offset ) {
                    interpret_raise_exception_with_bcalloc_message
                        ( /* err_code = */ -1,
                          /* message = */
                          "attempting to unpack values past the end of a blob",
                          /* module_id = */ 0,
                          /* exception_id = */ SL_EXCEPTION_BLOB_OVERFLOW,
                          ex );
                    return 0;
                }
            }

            if( count > ((alloccell_t*)array)[-1].length - start ) {
                interpret_raise_exception_with_bcalloc_message
                    ( /* err_code = */ -1,
                      /* message = */
                      "attempting to pack more values than array has",
                      /* module_id = */ 0,
                      /* exception_id = */ SL_EXCEPTION_ARRAY_OVERFLOW,
                      ex );
                return 0;
            }

            if( typechar != 'X' && typechar != 'x' ) {
                for( i = 0; i < count; i ++ ) {
                    if( pack_value( &array[start+i], typechar, size, offset,
                                    blob, pack, ex ) == 0 ) {
                        return 0;
                    }
                }
                start += count;
            } else {
                if( size <= 0 ) {
                    for( i = 0; i < count; i++ ) {
                        length = strnlen( (char*)blob + *offset,
                                          blob_header->size - *offset ) + 1;
                        *offset += length;
                    }
                } else {
                    *offset += size * count;
                }
            }
        }

        while( *description && *description != ',' )
            description++;
        if( *description )
            description++;
    }

    return 1;
}

int pack_array_layer( byte *blob, stackcell_t *array, char *description,
                      ssize_t *offset, ssize_t level,
                      int (*pack)( stackcell_t *stack_cell, 
                                   char typechar, ssize_t size, 
                                   ssize_t *offset, byte *blob ),
                      cexception_t *ex  )
{
    if( level == 0 ) {
	alloccell_t *blob_header = ((alloccell_t*)blob) - 1;

	assert( blob_header->magic == BC_MAGIC );

	BC_CHECK_PTR( array, ex );

	if( !pack_array_values( blob, array, description,
                                offset, pack, ex )) {
	    return 0;
	}
    } else {
	alloccell_t *header = (alloccell_t*)array;
	ssize_t layer_len = header[-1].length;
	ssize_t i;

        assert( array );

	for( i = 0; i < layer_len; i++ ) {
	    /* printf( ">>> packing element %d of layer %d\n", i, level ); */
	    if( !pack_array_layer( blob, STACKCELL_PTR( array[i] ), description,
                                   offset, level - 1, pack, ex  )) {
		return 0;
	    }
	}
    }
    return 1;
}

/*
** Unpacking of blob values:
 */

int unpack_value( stackcell_t *stack_cell, char typechar, ssize_t size,
                  ssize_t *offset, byte *blob,
                  int (*unpack)( stackcell_t *stack_cell, char typechar,
                                 ssize_t size, ssize_t *offset, byte *blob,
                                 cexception_t *ex ),
                  cexception_t *ex )
{
    int retval;
    alloccell_t *blob_header = ((alloccell_t*)blob) - 1;

    assert( blob_header->magic == BC_MAGIC );

    if( blob_header->size < size + *offset ) {
	interpret_raise_exception_with_bcalloc_message
	    ( /* err_code = */ -1,
	      /* message = */
	      "attempting to unpack values past the end of a blob",
	      /* module_id = */ 0,
	      /* exception_id = */ SL_EXCEPTION_BLOB_OVERFLOW,
	      ex );
	return 0;
    }

    retval = (*unpack)( stack_cell, typechar, size, offset, blob, ex );

    return retval;
}

int unpack_array_values( byte *blob, stackcell_t *array_stackcell,
                         char *description, ssize_t *offset,
                         int (*unpack)( stackcell_t *stack_cell, 
                                        char typechar, ssize_t size,
                                        ssize_t *offset, byte *blob,
                                        cexception_t *ex ),
                         cexception_t *ex )
{
    stackcell_t *array_ptr;
    alloccell_t *blob_header;
    char *descr_ptr;
    ssize_t size, length, count, start;
    char *count_str;
    char typechar;
    ssize_t i;

    assert( description );

    if( !blob ) return 1;

    blob_header = ((alloccell_t*)blob) - 1;
    count = 0;
    descr_ptr = description;
    while( *description ) {

        if( description[0] != 'X' && description[0] != 'x' ) {
            if( isdigit( description[1] )) {
                strtol( description + 1, &count_str, 0 );
                if( count_str && count_str[0] && isdigit( count_str[1] )) {
                    count += strtol( count_str + 1, NULL, 0 );
                } else {
                    count ++;
                }
            } else if( description[1] != '\0' && isdigit( description[2] )) {
                count += strtol( description + 2, NULL, 0 );
            } else {
                count ++;
            }
	}

        while( *description && *description != ',' )
            description++;
	if( *description )
	    description++;
    }

    array_ptr = bcalloc_array( sizeof(stackcell_t), count, 1, ex );
    BC_CHECK_PTR( array_ptr, ex );
    STACKCELL_SET_ADDR( *array_stackcell, array_ptr );

    description = descr_ptr;
    start = 0;
    while( *description ) {

	size = count = 0;
        typechar = description[0];
        if( isdigit( description[1] )) {
            if( description[0] != '\0' ) {
                size = strtol( description + 1, &count_str, 0 );
                if( count_str && count_str[0] && isdigit( count_str[1] )) {
                    count = strtol( count_str + 1, &description, 0 );
                } else {
                    count ++;
                }
            }
        } else if( description[1] != '\0' && isdigit( description[2] )) {
            count = strtol( description + 2, NULL, 0 );
        } else {
            count ++;
        }

        if( count > 0 ) {
            if( size > 0 ) {
                if( blob_header->size < size * count + *offset ) {
                    interpret_raise_exception_with_bcalloc_message
                        ( /* err_code = */ -1,
                          /* message = */
                          "attempting to unpack values past the end of a blob",
                          /* module_id = */ 0,
                          /* exception_id = */ SL_EXCEPTION_BLOB_OVERFLOW,
                          ex );
                    return 0;
                }
            }

            if( typechar != 'X' && typechar != 'x' ) {
                for( i = 0; i < count; i ++ ) {
                    if( unpack_value( &array_ptr[start + i], typechar,
                                      size, offset, blob,
                                      unpack, ex ) == 0 ) {
                        return 0;
                    }
                }
                start += count;
            } else {
                if( size <= 0 ) {
                    for( i = 0; i < count; i++ ) {
                        length = strnlen( (char*)blob + *offset,
                                          blob_header->size - *offset ) + 1;
                        *offset += length;
                    }
                } else {
                    *offset += size * count;
                }
            }
        }

        while( *description && *description != ',' )
            description++;
        if( *description )
            description++;
    }

    return 1;
}

void *unpack_array_layer( byte *blob, stackcell_t *array, char *description,
                          ssize_t *offset, ssize_t level,
                          int (*unpack)( stackcell_t *stack_cell, 
                                         char typechar, ssize_t size,
                                         ssize_t *offset, byte *blob,
                                         cexception_t *ex ),
                          cexception_t *ex  )
{
    if( level == 0 ) {
	if( !unpack_array_values( blob, array, description,
                                  offset, unpack, ex )) {
	    return NULL;
	}
    } else {
        stackcell_t *layer = STACKCELL_PTR(*array);
	alloccell_t *header = (alloccell_t*)layer;
	ssize_t layer_len = header[-1].length;
	ssize_t i;

        assert( layer );

	for( i = 0; i < layer_len; i++ ) {
	    /* printf( ">>> unpacking element %d of layer %d\n", i, level ); */
	    if( !unpack_array_layer( blob, &layer[i], description,
                                     offset, level - 1,
                                     unpack, ex )) {
                return NULL;
            }
	}
    }
    return array;
}
