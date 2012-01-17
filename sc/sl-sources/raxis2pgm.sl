#! /home/saulius/bin/sl0 --
#
# Read OSC image file(s) and print data in PGM format to STDOUT.
#

use std;

program ( argv : array of string; stdio : array of file );

var stdout = stdio[1];
var stderr = stdio[2];

for( var i = 1; i <= last(argv); i++ ) {
    try {
        var osc_image = fopen( argv[i], "r" );
	var header = new blob(2048);

	fseek( osc_image, 0 );
	//. "elements read =", fread( osc_image, header );
	fread( osc_image, header );

	var name = unpack string( header, 0, "s10" );

	if name != "RAXIS     " then
            <stderr> << argv[0] _ ": file '" _ argv[i] _ "' is not a RAXIS image\n";
	    continue
	endif

	var xoffset = 141 * 4 + 204;
	var yoffset = xoffset + 4;
	struct XY { x,y : int };
	var xy = struct XY {
 	    x : unpack int( header, xoffset, "I4" ),
 	    y : unpack int( header, yoffset, "I4" ),
        };

	## . "xpxl =", xy.x;
	## . "ypxl =", xy.y;

	var xwidth = unpack int( header, xoffset, "I4" );
	var ywidth = unpack int( header, yoffset, "I4" );
	var raster_offset = xwidth * 2;
	var buffer = new blob(xwidth * ywidth * 2);

	## . "raster ofset =", raster_offset;

	var int bytes;
	fseek( osc_image, raster_offset );
	bytes = fread( osc_image, buffer );
	## . bytes, "bytes read.";

	var raster = unpack int[xwidth][]( buffer, 0, "U2x%d" %% ywidth );
	## . "raster unpacked";

        # Output PGM image to STDOUT:

        . "P2";
        . length(raster[0]), length(raster);
        . 65535;

        var n = 0;
        for var x = 0 to last(raster) do
            for var y = 0 to last(raster[i]) do
                < 65535 - raster[x][y], "";
                n ++;
                if( n > 24 ) {
                    . "";
                    n = 0
                }
            enddo
            . "";
        enddo

	fclose( osc_image );
    }
    catch( var message : string ) {
        <stderr> << argv[0] _ ": " _ message _ "\n";
    }

    do . "" if i < last(argv);
}
