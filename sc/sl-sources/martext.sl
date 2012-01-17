#
# Snail compiler programs
#
#
# Read Mar image file(s) and print data in ASCII.
#

use std;

program ( argv : array of string );

for( var i = 1; i <= last(argv); i++ ) {
    . argv[i];
    try {
        var mar_image = fopen( argv[i], "r" );
	var bin_header_buffer = new blob(16*4);

	fread( mar_image, bin_header_buffer );

	var bin_header = unpack int[]( bin_header_buffer, 0, "i4x16" );

	for var j = 0 to last(bin_header) do
            < j; < "\t";
	    . bin_header[j];
	enddo

	fclose( mar_image );

    }
    catch( var message : string ) {
        . message;
    }

    do . "" if i < last(argv);
}
