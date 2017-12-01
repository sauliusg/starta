#! /bin/sh
#!perl -w # --*- Perl -*--
eval 'exec perl -x $0 ${1+"$@"}'
    if 0;
#------------------------------------------------------------------------------
#$Author$
#$Date$ 
#$Revision$
#$URL$
#------------------------------------------------------------------------------
#*
#  Read Raxis-IV .osc image.
#**

use strict;

for my $file (@ARGV) {
    open( IMAGE, $file ) or
	die( "could not open image '$file' for input -- $!" );

    print "$file\n";

    my $bin_header;
    my $bin_header_size = 1500;

    my $bytes_read = sysread( IMAGE, $bin_header, $bin_header_size );

    if( $bytes_read != $bin_header_size ) {
	warn( "file '$file' seems to be trincated" );
    }

    my $header_items = $bin_header_size / 4;
    my @header = unpack( "N$header_items", $bin_header );

    my $xwidth = $header[192];
    my $ywidth = $header[193];
    my $raster_offset = $xwidth * 2;

    print "X-width\t", $xwidth, "\n";
    print "Y-width\t", $ywidth, "\n";

    seek( IMAGE, $raster_offset, 0 );

    my @raster = ();

    for my $j (0..$xwidth-1) {
	my $line;
	my $bytes_read = sysread( IMAGE, $line, $ywidth * 2 );
	if( $bytes_read != $ywidth * 2 ) {
	    warn( "line $j of $file seems truncated" );
	    last;
	}
	$raster[$j] = [ unpack( "n$ywidth", $line ) ];
    }

    print $raster[0][0], " ", $raster[0][1], " ", $raster[0][2], "\n";
    print $raster[100][100], " ", $raster[100][101], " ", $raster[100][102];
    print "\n";

    close( IMAGE );
}
