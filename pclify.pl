#!/usr/bin/perl -w

use strict;
use Getopt::Long;

=head1 NAME

C<pclify.pl> - turn any image into an Ebix CBS logo PCL file

 takes any kind of image which is understood by ImageMagick
and turns into a PCL file which can be used by Ebix's CBS product as a 
logo for printouts.

=head1 SYNOPSIS

C<pclify.pl> C<--output> I<output_pcl_file> C<--size> I<W>C<x>I<H>
 C<[--input> I<source_image>C<]> C<[--dpi> I<resolution>C<]>
C<[--magick> I<convert_exe_path>C<]>

=head1 OPTIONS

=over 4

=item C<--output> I<output_pcl_file>

Where you want the PCL file to be created.

=item C<--size> I<W>C<x>I<H>

The geometry (width x height) in milimetres of the resulting image.

=item C<--input> I<source_image>

The image file you want converted. Defaults to STDIN. This can
be in any image format supported by ImageMagick.

=item C<--dpi> I<resolution>

How many dots-per-inch the image should come out as. Defaults to 600.
No checking is done to confirm where this is something that a printer can
conceivably do.

=item C<--magick> I<convert_exe_path>

Path name to find the C<convert> program from ImageMagick. Defaults to
just running C<convert> with no path, which will work if C<convert>
can be found in your C<PATH> environment variable.

=back


=head1 AUTHOR

Greg Baker

=cut

# Have to convert the original image with
#  convert -geometry WxH -monochrome -depth 1 sourcefile tempfile.pgm

my $source_filename = "-";
my $output_file = undef;
my $output_size = undef;
my $dpi = 600;
my $convert = "convert";
my $debugging = 0;
my $display_compression_stats = 0;

Getopt::Long::GetOptions(
			 'input:s' => \$source_filename,
			 'output:s' => \$output_file,
			 'dpi:i' => \$dpi,
			 'size:s' => \$output_size,
			 'magick:s' => \$convert,
			 'debug!' => \$debugging,
			 'compression-stats!' => $display_compression_stats
			 );

die "--size must be specified as width x depth (in mm)"
  unless defined $output_size and $output_size =~ /^([0-9.]+)\s*x\s*([0-9.]+)$/;

die "--output must be specified" unless defined $output_file;

my $output_height = $2;
my $output_width = $1;

my $pixels_wide = int(($dpi * $output_width / 25.4) / 8) * 8;
my $pixels_high = int($dpi * $output_height / 25.4);


my $compressed_rows = 0;

open(IMG_FILE,"$convert -geometry ${pixels_wide}x${pixels_high}! -monochrome -depth 1 \"$source_filename\" pgm:- |") || die "can't convert $source_filename";
binmode(IMG_FILE);
print STDERR "$convert -geometry ${pixels_wide}x${pixels_high}! -monochrome -depth 1 \"$source_filename\" pgm:-\n" if $debugging;


open(PCL_FILE,">$output_file") || die "can't write to $output_file";
binmode(PCL_FILE);

my $line = <IMG_FILE>;
chomp $line;
die "I only understand PPM format P6" unless $line =~ /P([56])/;

# P6 format has R,G,B components which we ignore. P5 is shorter.
my $skip_width = $1 == 6 ? 2 : 0;

my $geometry = <IMG_FILE>;
chomp $geometry;

die "Couldn't understand the geometry" unless $geometry =~ /^(\d+)\s*(\d+)$/;
my $width = $1;
my $height = $2;

die "width has to be divisible by 8, which $width isn't" unless $width % 8 == 0;
my $byte_width = $width / 8;


my $depth = <IMG_FILE>;
chomp $depth;

die "I can only cope with one bit data files (not $depth)" unless $depth == 1;

my $esc = "\033";

my $dpi_intro = "${esc}*t${dpi}R";
my $raster_start = "${esc}*r1A";
my $uncompressed_data_format = "${esc}*b0M";
my $run_length_compressed_data_format = "${esc}*b1M";
my $raster_end = "${esc}*rB";


my $current_data_format = undef;
print PCL_FILE "$dpi_intro$raster_start";
my $x;
my $y;
my $z;
for ($y=0;$y<$height;$y++) {
  my @uncompressed_data;
  for ($x=0;$x<$byte_width;$x++) {
    # It might be easier to unpack() for this for loop.
    my $output_byte = 0;
    for ($z=7;$z>=0;$z--) {
      my $minus_z = 8-$z;
      my $input_pixel;
      read(IMG_FILE,$input_pixel,1) || die "read error on pixel $x,$y, byte $minus_z";
      die "invalid data ".(ord($input_pixel))." at $x,$y byte $minus_z" unless
	ord($input_pixel) == 0 or ord($input_pixel) == 1;
      my $bit = !ord($input_pixel);
      # Because this is P6 format, which R,G and B components (all of
      # which will be the same)
      read(IMG_FILE,$input_pixel,$skip_width);
      $output_byte |= ($bit << $z);
    }
    # Store that output byte in both run-length encoded version
    # and uncompressed versions.
    push(@uncompressed_data,$output_byte);
  }
  my @run_length_compressed = run_length_compress(@uncompressed_data);
  my $this_data_blob;
  my $which_data;
  if ($#uncompressed_data > $#run_length_compressed) {
    $this_data_blob = $run_length_compressed_data_format;
    $which_data = \@run_length_compressed;
    $compressed_rows += 1;
    #print STDERR "Uncompressed version: ".join(" ",@uncompressed_data).
    #  "\n Compressed version: ".join(" ",@run_length_compressed)."\n";
  } else {
    $this_data_blob = $uncompressed_data_format;
    $which_data = \@uncompressed_data;
  }
  if (not defined $current_data_format or 
      $current_data_format ne $this_data_blob) {
    $current_data_format = $this_data_blob;
    print PCL_FILE $current_data_format;
  }
  print PCL_FILE &raster_data(1+$#$which_data);
  print PCL_FILE join("",map(chr,@$which_data));
}

#my $where = tell(IMG_FILE);
#my @stat_struct = stat(IMG_FILE);
#if ($stat_struct[7] != $where) {
#  die "The file is $stat_struct[7] bytes long, and we have only read $where bytes";
#}

print PCL_FILE $raster_end;
close(PCL_FILE);
close(IMG_FILE);

print STDERR "$compressed_rows rows were compressed out of $height\n";
#  if $display_compression_stats;

sub run_length_compress {
  my $repeated_byte = undef;
  my $repeat_count = 0;

  #my $repeated_byte = 255;
  #my $repeat_count = 1;
  #shift;

  my $output_byte;
  my @compressed_data = ();
  foreach $output_byte (@_) {
    if (not defined $repeated_byte) {
      $repeated_byte = $output_byte;
      $repeat_count = 0;
    }
    if ($repeated_byte == $output_byte) {
      $repeat_count += 1;
      if ($repeat_count == 256) {
	push(@compressed_data,255,$repeated_byte);
	$repeat_count = 0;
      }
    } else {
      push(@compressed_data,$repeat_count-1,$repeated_byte);
      $repeated_byte = $output_byte;
      $repeat_count = 1;
    }
  }
  if ($repeat_count != 0) {
    push(@compressed_data,$repeat_count-1,$repeated_byte);
  }
  return @compressed_data;
}

sub raster_data {
  my $number_of_bytes = shift;
  return "${esc}*b${number_of_bytes}W";
}
