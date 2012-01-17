#
# Snail compiler programs
#
#
# Read OSC image file(s) and print data in ASCII.
#

use std;

program ( argv : array of string );

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

inline bytecode function i2b( m : array of int ) : array of byte {};

inline bytecode function s2b( m : array of short ) : array of byte {};

procedure swapd( m : array of int )
{
    if false then
        var b = i2b( m );
        for var i = 0 to last(m) do
            b[4*i], b[4*i+1], b[4*i+2], b[4*i+3] = b[4*i+3], b[4*i+2], b[4*i+1], b[4*i];
        enddo;
    else
        bytecode begin PLD %m ASWAPD end;
    endif
}

// procedure swapw( m : array of short )
// {
//     if false then
//         var b = s2b( m );
//         for var i = 0 to last(m) do
//             b[2*i], b[2*i+1] = b[2*i+1], b[2*i];
//         enddo;
//     else
//         bytecode begin PLD %m ASWAPW end;
//     endif
// }

inline bytecode procedure swapw( m : array of short )
{
    ASWAPW
} 

for( var i = 1; i <= last(argv); i++ ) {
    . argv[i];
    try {
        var osc_image = fopen( argv[i], "r" );
	var bin_header = new int[1500];

	// reverse-egineered from MOSFLM code:

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

	// for var j = 200 to 207 do
        //     < "code "; < j; < "?\t"; . i2f( bin_header[j] );
        // enddo

	< "wavelen\t"; . i2f( bin_header[73] );
	< "dist\t";    . i2f( bin_header[86] );
	< "phi0\t";    . i2f( bin_header[131] );
	< "phie\t";    . i2f( bin_header[132] );
	< "beamX\t";   . i2f( bin_header[135] );
	< "beamY\t";   . i2f( bin_header[136] );

	var xwidth = bin_header[192];
	var ywidth = bin_header[193];
	var raster_offset = xwidth * 2;
	var raster = new short[xwidth][ywidth];

	// . raster_offset;
	fseek( osc_image, raster_offset );
	for var j = 0 to last(raster) do
	    fread( osc_image, raster[j] );
	    swapw( raster[j] );
  	enddo

	< raster[0][0]; < " "; < raster[0][1]; < " "; < raster[0][2]; < " ";
	."";
	< raster[100][100]; < " "; < raster[100][101]; < " "; < raster[100][102]; < " ";
	."";

	fclose( osc_image );
    }
    catch( var message : string ) {
        . message;
    }

    do { . "" } if i < last(argv);
}
