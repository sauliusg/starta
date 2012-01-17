
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stdlib.h>
#include <RaxisHeader.h>
#include <assert.h>

static char *progname;

typedef unsigned short pixelval_t;

void swapint( void *buffer, ssize_t size );
pixelval_t **alloc_matrix( ssize_t x, ssize_t y );
void free_matrix( pixelval_t **matrix, ssize_t x );

ssize_t load_raster( FILE *in, pixelval_t **raster, ssize_t xsize, ssize_t ysize,
		     ssize_t raster_offset );

int main( int argc, char **argv )
{
    int i;
    int retval = 0;
    int nread;
    ssize_t errval;
    ssize_t raster_offset;
    pixelval_t **raster;
    long long sum;
    ssize_t ix, iy;
    long long linesum;

    progname = argv[0];

    if( argc > 1 ) {
	for( i = 1; i < argc; i++ ) {
	    struct RigakuHeader header;
	    FILE *in = fopen( argv[i], "r" );
	    if( !in ) {
		fprintf( stderr, "%s: %s: ERROR, can not open file "
			 "'%s' for input - %s\n", progname, argv[i],
			 argv[i], strerror(errno) );
		retval = 1;
		continue;
	    }
	    nread = fread( &header, sizeof(header), 1, in );
	    if( nread != 1 ) {
		fprintf( stderr, "%s: %s: ERROR, failed to read "
			 "%d bytes from the file\n", progname, argv[i],
			 sizeof(header));
		retval = 2;
		fclose( in );
		continue;
	    }

	    swapint( &header.xpxl, 1 );
	    swapint( &header.zpxl, 1 );

	    printf( "X size = %d\n", header.xpxl );
	    printf( "Y size = %d\n", header.zpxl );

	    raster = alloc_matrix( header.xpxl, header.zpxl );

	    if( !raster ) {
		fprintf( stderr, "%s: %s: ERROR, failed to allocate "
			 "raster %d x %d\n", progname, argv[i],
			 header.xpxl, header.zpxl );
		retval = 3;
		fclose( in );
		continue;		
	    }

	    raster_offset = header.xpxl * 2;

	    if( (errval = load_raster( in, raster, header.xpxl, header.zpxl,
				       raster_offset )) != 0 ) {
		fprintf( stderr, "%s: %s: ERROR, could not read "
			 "raster %d x %d at line %d - %s\n", progname, argv[i],
			 header.xpxl, header.zpxl, errval,
			 errno == 0 ? "file too short" : strerror(errno));
		retval = 3;
		fclose( in );
		continue;		
	    }

	    printf( "%d %d %d\n", raster[0][0], raster[0][1], raster[0][2] );
	    printf( "%d %d %d\n",
		    raster[100][100], raster[100][101], raster[100][102] );

	    sum = 0;
	    for( ix = 0; ix < header.xpxl; ix ++ ) {
		linesum = 0;
		for( iy = 0; iy < header.zpxl; iy ++ ) {
		    linesum += (int)(raster[ix][iy]);
		}
		sum += linesum;
	    }
	    printf( "%s: pixel sum %lld\n", argv[i], sum );
	    printf( "%s: number of pixels %d\n", argv[i],
		    header.xpxl * header.zpxl );
	    printf( "%s: average pixel value %g\n", argv[i],
		    (double)sum / (double)(header.xpxl * header.zpxl) );

	    free_matrix( raster, header.xpxl );
	    fclose( in );
	}
    } else {
	fprintf( stderr, "%s: WARNING, no file names provided "
		 "on the command line\n", progname );
    }

    return retval;
}

void swapint( void *buffer, ssize_t size )
{
    ssize_t i;
    char *bytes = buffer;
    char tmp;

    for( i = 0; i < 4 * size; i += 4 ) {
	tmp = bytes[i];
	bytes[i] = bytes[i+3];
	bytes[i+3] = tmp;
	tmp = bytes[i+1];
	bytes[i+1] = bytes[i+2];
	bytes[i+2] = tmp;
    }
}

void swapshort( void *buffer, ssize_t size )
{
    ssize_t i;
    char *bytes = buffer;
    char tmp;

    for( i = 0; i < 2 * size; i += 2 ) {
	tmp = bytes[i];
	bytes[i] = bytes[i+1];
	bytes[i+1] = tmp;
    }
}

pixelval_t **alloc_matrix( ssize_t xsize, ssize_t ysize )
{
    pixelval_t **m;
    ssize_t i;

    m = calloc( xsize, sizeof(m[0]) );
    if( !m ) return NULL;

    for( i = 0; i < xsize; i++ ) {
	m[i] = calloc( ysize, sizeof(m[0][0]) );
	if( !m[i] ) {
	    free_matrix( m, xsize );
	    return NULL;
	}
    }

    return m;
}

void free_matrix( pixelval_t **m, ssize_t xsize )
{
    ssize_t i;

    if( !m ) return;

    for( i = 0; i < xsize; i++ ) {
	if( m[i] ) {
	    free( m[i] );
	}
    }
    free( m );
}

/* 'load_raster()' return 0 on success, non-zero error code on
   failure.  Negative values are error codes, positive values are
   1-based line numbers where the error occured. */

ssize_t load_raster( FILE *in, pixelval_t **raster, ssize_t xsize, ssize_t ysize,
		     ssize_t raster_offset )
{
    ssize_t i;
    ssize_t nread;

    assert( in );
    assert( raster );

    if( fseek( in, raster_offset, SEEK_SET ) != 0 ) {
	return -1;
    }

    for( i = 0; i < xsize; i++ ) {
	nread = fread( raster[i], sizeof(raster[0][0]), ysize, in );
	if( nread != ysize ) {
	    return i+1;
	}	
	swapshort( raster[i], ysize );
    }

    return 0;
}
