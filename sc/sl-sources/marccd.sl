#
# Snail compiler programs
#
#
# Read MARCCD image file(s) and print data in ASCII.
#

use std;

program ( argv : array of string; stdio : array of file );

var stdout = stdio[1];

struct TagDescription {
    tag  : int;
    name : string
}

var TIIF_tag_names = [
    /* Tag names from FileFormat.Info, page "The TIFF File Format": */
    struct TagDescription { tag => 254, name => "NewSubfileType" },
    struct TagDescription { tag => 255, name => "SubfileType" },
    struct TagDescription { tag => 256, name => "ImageWidth" },
    struct TagDescription { tag => 257, name => "ImageLength" },
    struct TagDescription { tag => 258, name => "BitsPerSample" },
    struct TagDescription { tag => 259, name => "Compression" },
    struct TagDescription { tag => 262, name => "PhotometricInterpretation" },
    struct TagDescription { tag => 263, name => "Threshholding" },
    struct TagDescription { tag => 269, name => "DocumentName" },
    struct TagDescription { tag => 270, name => "ImageDescription" },
    struct TagDescription { tag => 271, name => "Make" },
    struct TagDescription { tag => 272, name => "Model" },
    struct TagDescription { tag => 273, name => "StripOffsets" },
    struct TagDescription { tag => 274, name => "Orientation" },
    struct TagDescription { tag => 277, name => "SamplesPerPixel" },
    struct TagDescription { tag => 278, name => "RowsPerStrip" },
    struct TagDescription { tag => 279, name => "StripByteCounts" },
    struct TagDescription { tag => 282, name => "XResolution" },
    struct TagDescription { tag => 283, name => "YResolution" },
    struct TagDescription { tag => 284, name => "PlanarConfiguration" },
    struct TagDescription { tag => 285, name => "PageName" },
    struct TagDescription { tag => 286, name => "XPosition" },
    struct TagDescription { tag => 287, name => "YPosition" },
    struct TagDescription { tag => 290, name => "GrayResponseUnit" },
    struct TagDescription { tag => 291, name => "GrayResponseCurve" },
    struct TagDescription { tag => 292, name => "Group3Options" },
    struct TagDescription { tag => 293, name => "Group4Options" },
    struct TagDescription { tag => 296, name => "ResolutionUnit" },
    struct TagDescription { tag => 297, name => "PageNumber" },
    struct TagDescription { tag => 301, name => "ColorResponseCurves" },
    struct TagDescription { tag => 305, name => "Software" },
    struct TagDescription { tag => 306, name => "DateTime" },
    struct TagDescription { tag => 315, name => "Artist" },
    struct TagDescription { tag => 316, name => "HostComputer" },
    struct TagDescription { tag => 317, name => "Predictor" },
    struct TagDescription { tag => 318, name => "ColorImageType" }, /* ???? */
    struct TagDescription { tag => 318, name => "White Point" },    /* ???? */
    struct TagDescription { tag => 319, name => "ColorList" },
    struct TagDescription { tag => 329, name => "PrimaryChromaticities" },
    struct TagDescription { tag => 320, name => "ColorMap" },
];

function lookup_tag_name( int tag; TagDescription[] table ) : string
{
    for var int i = 0 to last(table) do
        if table[i].tag == tag then
            return table[i].name
        endif
    enddo
    return "";
}

for( var i = 1; i <= last(argv); i++ ) {
    . argv[i];
    try {
        var image_file = fopen( argv[i], "r" );
	var header = new blob(8);

	fseek( image_file, 0 );
	//. "elements read =", fread( image_file, header );
	fread( image_file, header );

	var name = unpack string( header, 0, "c2" );

        . name;

	if name != 'II' && name != 'MM' then
            . "Not a MAR CCD (TIFF) image";
	    continue
	endif

        var tiff_version_number =
            unpack int( header, 2, name == "II" ? "i2" : "I2" );

        var tiff_dir_offset =
            unpack int( header, 4, name == "II" ? "i4" : "I4" );

        . tiff_version_number;
        . tiff_dir_offset;

        fseek( image_file, tiff_dir_offset );

        var tiff_directory_header = new blob(2);
        fread( image_file, tiff_directory_header );

        var nentries = unpack int( tiff_directory_header, 0, 
                                   name == "II" ? "i2" : "I2" );

        . nentries;

        const tiff_dir_entry_length = 6;
        const tiff_dir_entry_size = tiff_dir_entry_length * 2;

        var tiff_directory_buffer =
            new blob( const(tiff_dir_entry_size) * nentries + 4 );

        fread( image_file, tiff_directory_buffer );

        type TIFF_directory_entry = struct {
            tag : int;
            tag_name : string;
            tag_type : int;
            tag_length : int;
            tag_value : int;
            tag_offset : llong;
        }

        var tiff_directory = new TIFF_directory_entry[nentries];
        
        for var ii = 0 to last(tiff_directory) do
            var entry = struct TIFF_directory_entry {
                tag => 
                    unpack int(tiff_directory_buffer, 
                    ii * const(tiff_dir_entry_size),
                    name == "II" ? "u2" : "U2" ),
                tag_type => 
                    unpack int(tiff_directory_buffer, 
                    ii * const(tiff_dir_entry_size) + 2, 
                    name == "II" ? "u2" : "U2" ),
                tag_length => 
                    unpack int(tiff_directory_buffer, 
                    ii * const(tiff_dir_entry_size) + 4,
                    name == "II" ? "u4" : "U4" )
            };
            entry.tag_name = lookup_tag_name( entry.tag, TIIF_tag_names );
            if( entry.tag_type == 5 or entry.tag_length <= 4 ) {
                entry.tag_value = unpack int( tiff_directory_buffer,
                ii * const(tiff_dir_entry_size) + 8, 
                name == "II" ? "u4" : "U4" )
            } else {
                entry.tag_offset = unpack llong(tiff_directory_buffer,
                ii * const(tiff_dir_entry_size) + 4,
                name == "II" ? "u4" : "U4" )
            }
            tiff_directory[ii] = entry;
        enddo;

        . length(tiff_directory);

        for var ii = 0 to last(tiff_directory) do
            < ii+1, "\t";
            < "%d\t" %% tiff_directory[ii].tag;
            < "%-27s\t" %% tiff_directory[ii].tag_name;
            < "%d\t" %% tiff_directory[ii].tag_type;
            < "%d\t" %% tiff_directory[ii].tag_length;
            < "%15d\t" %% tiff_directory[ii].tag_value;
            < "%15d\t" %% tiff_directory[ii].tag_offset;
            . "";
        enddo;

        . unpack int( tiff_directory_buffer, 12 * nentries, "i4" );

	fclose( image_file );
    }
    catch( var message : string ) {
        . message;
    }

    do . "" if i < last(argv);
}
