#
# Snail compiler programs
#
#
# Read OSC image file(s) and print data in ASCII.
#

use std;

// include "RaxisHeader.snl"

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
	var header = new blob(2048);

	fseek( osc_image, 0 );
	//. "elements read =", fread( osc_image, header );
	fread( osc_image, header );

	var name = unpack char[]( header, 0, "i1x10" );

	if !chararrayeq( name, raxis ) then
            . "Not a RAXIS image";
	    continue
	endif

	< ">>";
	for var ii = 0 to last( name ) do
	    < name[ii];
        enddo
	< "<<";
	. "";
	. length( name );
	< ">>";
	var version = unpack char[]( header, 10, "i1x10" );
	for var ii = 0 to last( version ) do
	    < version[ii];
        enddo
	< "<<";
	. "";

	var xoffset = 141 * 4 + 204;
	var yoffset = xoffset + 4;
	struct XY { x,y : int };
	var xy = struct XY {
 	    x : unpack int( header, xoffset, "I4" ),
 	    y : unpack int( header, yoffset, "I4" ),
        };

	. "xpxl =", xy.x;
	. "ypxl =", xy.y;

	< "X-pixel\t"; . unpack float( header, 194*4, "F4" );
	< "Y-pixel\t"; . unpack float( header, 195*4, "F4" );

	< "extra?\t";  . unpack short( header, 196*4, "I4" );
	< "extra?\t";  . unpack short( header, 197*4, "I4" );
	< "code1?\t";  . unpack short( header, 198*4, "I4" );
	< "code2?\t";  . unpack short( header, 199*4, "I4" );

	< "wavelen\t"; . unpack float( header,  73*4, "F4" );
	< "dist\t";    . unpack float( header,  86*4, "F4" );
	< "phi0\t";    . unpack float( header, 131*4, "F4" );
	< "phie\t";    . unpack float( header, 132*4, "F4" );
	< "beamX\t";   . unpack float( header, 135*4, "F4" );
	< "beamY\t";   . unpack float( header, 136*4, "F4" );

//	swapd( header );
//
//	. header.wlng;
//	. header.phi0;
//	. header.phis;
//	. header.phie;
//	. header.xpxl;
//	. header.zpxl;
//	. header.cyld;
//	. "";
//
//	fseek( osc_image, 0 );
//	fread( osc_image, bin_header );
//	swapd( bin_header );
//
//	< "X-width\t"; . bin_header[192];
//	< "Y-width\t"; . bin_header[193];
//
//	< "X-pixel\t"; . i2f( bin_header[194] );
//	< "Y-pixel\t"; . i2f( bin_header[195] );
//
//	< "extra?\t";  . bin_header[196];
//	< "extra?\t";  . bin_header[197];
//
//	< "code1?\t";  . bin_header[198];
//	< "code2?\t";  . bin_header[199];
//
//	< "wavelen\t"; . i2f( bin_header[73] );
//	< "dist\t";    . i2f( bin_header[86] );
//	< "phi0\t";    . i2f( bin_header[131] );
//	< "phie\t";    . i2f( bin_header[132] );
//	< "beamX\t";   . i2f( bin_header[135] );
//	< "beamY\t";   . i2f( bin_header[136] );
//
	var xwidth = unpack int( header, xoffset, "I4" );
	var ywidth = unpack int( header, yoffset, "I4" );
	var raster_offset = xwidth * 2;
	var buffer = new blob(xwidth * ywidth * 2);

	. "raster ofset =", raster_offset;

	var int bytes;
	fseek( osc_image, raster_offset );
	bytes = fread( osc_image, buffer );
	. bytes, "bytes read.";

	var raster = unpack int[xwidth][]( buffer, 0, "U2x%d" %% ywidth );
	. "raster unpacked";

	var sum : llong;
	for var ii = 0 to last(raster) do
            var linesum : llong;
	    for var jj = 0 to last(raster[ii]) do
	        linesum += <llong>raster[ii][jj]
            enddo
            sum += linesum;
            ## < linesum; < "\t"; < sum; < "\n";
        enddo
        . sum;
	. <double>sum;
	. <double>xwidth;
	. <double>ywidth;
	. <double>xwidth * <double>ywidth;

	<stdout> << "average = " <<  <double>sum / <double>(xwidth * ywidth) << "\n";

	. raster[0][0], raster[0][1], raster[0][2];
	. raster[100][100], raster[100][101], raster[100][102];

	fclose( osc_image );
    }
    catch( var message : string ) {
        . message;
    }

    do . "" if i < last(argv);
}
