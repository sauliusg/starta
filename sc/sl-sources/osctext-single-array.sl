#
# Snail compiler programs
#
#
# Read OSC image file(s) and print data in ASCII.
#

use std;

include "RaxisHeader.snl"

program ( argv : array of string; stdio : array of file );

var stdout = stdio[1];

inline function printchars( a : array of char )
{
    for var i = 0 to last(a) do
        if a[i] == '\0'c then
            < "."
	    // break
	else
	    < a[i]
	endif
    enddo
}

inline bytecode function i2f( m : int ) : float {};

inline bytecode function i2b( m : ref ) : array of byte {};

inline bytecode function s2b( m : ref ) : array of byte {};

procedure swapd( m : ref )
{
    if false then
        var b : array of byte = i2b( m );
        for var i = 0 to last(b) do
            b[4*i], b[4*i+1], b[4*i+2], b[4*i+3] = b[4*i+3], b[4*i+2], b[4*i+1], b[4*i];
        enddo;
    else
        bytecode begin PLD %m ASWAPD end;
    endif
}

procedure swapw( m : ref )
{
    if false then
        var b = s2b( m );
        for var i = 0 to last(b) do
            b[2*i], b[2*i+1] = b[2*i+1], b[2*i];
        enddo;
    else
        bytecode { PLD %m ASWAPW };
    endif
}

function chararrayeq( a1, a2 : array of char ) : bool
{
     if length(a1) != length(a2) then return false; endif;

     for var int i = 0 to last( a1 ) do
         if a1[i] != a2[i] { return false }
     enddo

     return true;
}

var raxis = [ 'R'c, 'A'c, 'X'c, 'I'c, 'S'c, ' 'c, ' 'c, ' 'c, ' 'c, ' 'c ];

for( var i = 1; i <= last(argv); i++ ) {
    . argv[i];
    try {
        var osc_image = fopen( argv[i], "r" );
	var struct_header = new RigakuHeader;
	var bin_header = new int[1500];

	fseek( osc_image, 0 );
	//. "elements read =", fread( osc_image, struct_header );
	fread( osc_image, struct_header );

	if !chararrayeq( struct_header.name[], raxis ) then
            . "Not a RAXIS image";
	    continue
	endif

	< ">>";
	for var ii = 0 to 9 do
	    < struct_header.name[ii];
        enddo
	< "<<";
	. "";
	. length( struct_header.name[] );
	< ">>";
	for var ii = 0 to 9 do
	    < struct_header.vers[ii];
        enddo
	< "<<";
	. "";

	swapd( struct_header );

	. struct_header.wlng;
	. struct_header.phi0;
	. struct_header.phis;
	. struct_header.phie;
	. struct_header.xpxl;
	. struct_header.zpxl;
	. struct_header.cyld;
	. "";

	fseek( osc_image, 0 );
	fread( osc_image, bin_header );
	swapd( bin_header );

	< "X-width\t"; . bin_header[192];
	< "Y-width\t"; . bin_header[193];

	< "X-pixel\t"; . i2f( bin_header[194] );
	< "Y-pixel\t"; . i2f( bin_header[195] );

	< "extra?\t";  . bin_header[196];
	< "extra?\t";  . bin_header[197];

	< "code1?\t";  . bin_header[198];
	< "code2?\t";  . bin_header[199];

	< "wavelen\t"; . i2f( bin_header[73] );
	< "dist\t";    . i2f( bin_header[86] );
	< "phi0\t";    . i2f( bin_header[131] );
	< "phie\t";    . i2f( bin_header[132] );
	< "beamX\t";   . i2f( bin_header[135] );
	< "beamY\t";   . i2f( bin_header[136] );

	var xwidth = bin_header[192];
	var ywidth = bin_header[193];
	var raster_offset = xwidth * 2;
	## var raster = new short[xwidth][ywidth];
	var raster = new short[<llong>xwidth * <llong>ywidth];

	. "raster ofset =", raster_offset;
	var int bytes;
	fseek( osc_image, raster_offset );
	## for var j = 0 to last(raster) do
	##     bytes += fread( osc_image, raster[j] );
	##     swapw( raster[j] );
  	## enddo
        bytes = fread( osc_image, raster );
        swapw( raster );

	. bytes, "bytes read.";

	var sum : llong;
	for var ii = 0 to last(raster) do
	    sum += <llong>raster[ii]
        enddo
        . sum;
	. <double>sum;
	. <double>xwidth;
	. <double>ywidth;
	. <double>xwidth * <double>ywidth;

	<stdout> << "average = " <<  <double>sum / <double>(xwidth * ywidth) << "\n";

	. raster[0], raster[1], raster[2];
	## . raster[100][100], raster[100][101], raster[100][102];

	fclose( osc_image );
    }
    catch( var message : string ) {
        . message;
    }

    do . "" if i < last(argv);
}
