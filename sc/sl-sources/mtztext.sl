#
# Snail compiler programs
#
#
# Read MTZ file(s) and print data in ASCII.
#

use std;

inline bytecode function ord( c : char ): int
{
    HEXTEND EXTEND
}

function isdigit( char c ): bool
{
    return ord(c) >= ord('0'c) && ord(c) <= ord('9'c)
}

function atoi( s : string ) : int
{
    var value = 0;

    for var int i = 0 to last(s) do
        if( !isdigit( s[i] ) ) {
            return value;
        }
        value += ord(s[i]) - ord( '0'c );
    enddo;
    return value;
}

program ( argv : array of string );

inline function printchars( a : array of char )
{
    for var i = 0 to last(a) do
    	do break if a[i] == '\0'c;
        < a[i]
    enddo
}

inline bytecode procedure swapd( m : blob )
{
    ASWAPD
} 

for( var i = 1; i <= last(argv); i++ ) {
    // . argv[i];
    try {
        var mtz = fopen( argv[i], "r" );
	var signature = new blob(4);
	var offset = new blob(4);
	var mstamp = new blob(4);

	fread( mtz, signature );
	fread( mtz, offset );
	fread( mtz, mstamp );
	< "'";
        printchars( unpack char[] ( signature, 0, "i1x4" ));
        < "'\n";

	if( ( unpack char (mstamp, 0, "i1" ) & '\0xF0'c) == '\0x10'c ) {
	     . "Big endian file, will swap bytes...";
             swapd( offset )
        }

	. unpack int (offset, 0, "i4");

	fseek( mtz, (unpack int(offset, 0, "i4") - 1) * 4 );

	var line = new blob(80);

        {
	    var int j = 1;
	    var long read;
	    while( (read = fread( mtz, line )) == length(line) ) {
                < j; < "\t"; // < read; < "\t";
            	printchars( unpack char[]( line, 0, "i1x4" ));
		< "\t" _ unpack string (line, 4, "s");
	    	. "";
                if( unpack string (line, 0, "s4") == "END " ) {
		    break;
 		}
            	j ++;
	    }
        };

        {
	    var int j = 1;
	    var long read;
	    read = fread( mtz, line );
            var histline = unpack string (line, 0, "s");
	    if( unpack string (line, 0, "s7") == "MTZHIST" ) {
	        var start = 7;
                do start++ while start <= last(histline) && !isdigit(histline[start]);
		// . ">>> history number start:", start;
	        .  "\t" _ unpack string (line, 0, "s");
                var nhist = atoi( unpack string (line, start, "s" ));
                // . ">>> history lines:", nhist;
	        for j = 1 to nhist { 
                    read = fread( mtz, line );
		    if( read != <long>length(line) ) { break };
                    < j; < "\t"; // < read; < "\t";
		    < unpack string (line, 0, "s");
	    	    . "";
                    if( unpack string (line, 0, "s16") == "MTZENDOFHEADERS" ) {
		        break;
 		    }
            	    j ++;
	    	}
            }
	}

        {
	    var int j = 1;
	    var batch_line = new blob(70);
	    var batch_header = new blob(70*10);
	    var long read;
	    OUTER: 
            while( (read = fread( mtz, batch_line )) == length(batch_line) ) {
                < j; < "\t"; // < read; < "\t";
		< unpack string (batch_line, 0, "s");
	    	. "";
		for var l = 2 to 4 {
		    if( (read = fread( mtz, batch_line )) != length(batch_line) ) {
		        break OUTER
                    }
                    < "\t"; // < read; < "\t";
		    < unpack string (batch_line, 0, "s");
	    	    . "";
		}
                if( unpack string (batch_line, 0, "s4") == "MTZENDOFHEADERS" ) {
		    break;
 		}
            	j ++;
	        if( (read = fread( mtz, batch_header )) != length(batch_header)) {
		    ## . ">>> finishing batch headers after reading", read, "bytes";
		    break
		} else {
		    ## . ">>> continuing batch headers after reading", read, "bytes";

		    var floats = unpack float[] (batch_header, 29 * 4, "r4x"_"%d"%%((length(batch_header)/4)-29));
		    for var ii = 0 to last( floats ) do
		        < floats[ii], " ";
		    enddo
		    . "\n>>>>";

		    var ints   = unpack int[] (batch_header, 0, "i4x29");
		    for var ii = 0 to last( ints ) do
		        < ints[ii], " ";
		    enddo
		    . "\n>>>>";
		}
	    }
	}

	fclose( mtz );
	do . "" if i < last(argv);
    }
    catch( var message : string ) {
        . message;
    }
}
