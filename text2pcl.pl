#!/usr/bin/perl -w

use strict;
use English;

=head1 NAME

C<text2pcl.pl> - turn text an Ebix CBS logo PCL file

=head1 SYNOPSIS

C<text2pcl.pl> [input files...]

=head1 SUPPORTED COMMANDS

=over 4

=item set font arial [size]

=item set font courier [size]

=item set lines per inch [lpi]

=item set lines per cm [lpi]

=item set line height [height] inches

=item set line height [height] cm

=item **bolded text**

=item //italic text//

=item __underlined text__

=back

=head1 AUTHOR

Greg Baker

=cut

# PCL uses Windows-format line endings
if ($OSNAME !~ "MSWin") {
  $OUTPUT_RECORD_SEPARATOR = "\r\n";
  $INPUT_RECORD_SEPARATOR = "\r\n";
}

my %font_ids = ( arial => 16602, courier => 0 );
my %length_conversions = ( inch => 1, cm => 2.54, mm => 25.4 , inches => 1 );

my $esc = "\033";
my $bold_on = $esc."(s3B";
my $bold_off = $esc."(s0B";
my $italic_on = $esc."(ss1V";
my $italic_off = $esc."(ss1V";
my $underline_on = $esc."&d0D";
my $underline_off = $esc."&d@";
my $line;
INPUT_LINE:
while ($line = <>) {
  if ($line =~ /^\s*set\s*font\s*(\w+)\s*(\d+)\s*$/i) {
    my $font_name = lc $1;
    die "Unknown font at line $.: $font_name" unless exists $font_ids{$font_name};
    my $font_num = $font_ids{$font_name};
    my $font_size = $2;
    print "${esc}(s${font_num}t0b0s${font_size}v1P";
    next INPUT_LINE;
  }

  if ($line =~ /^\s*set\s*lines\s*per\s*(\w*)\s*([0-9.]+)\s*$/i) {
    my $units = lc $1;
    die "unknown units at line $. $units" unless exists $length_conversions{$units};
    my $lpi = $2;
    my $line_spacing = $length_conversions{$units} * 48.0 / $lpi;
    my $l_output = sprintf ("%.2f",$line_spacing);
    print "${esc}&l${l_output}C";
    next INPUT_LINE;
  }

  if ($line =~ /^\s*set\s*line\s*height\s*([0-9.]+)\s*(\w+)/i) {
    my $units = lc $2;
    die "unknown units at line $. $units" unless exists $length_conversions{$units};
    my $line_spacing = $length_conversions{$units} * $1 * 48.0;
    my $l_output = sprintf ("%.2f",$line_spacing);
    print "${esc}&l${l_output}C";
    next INPUT_LINE;
  }

  $line =~ s/\*\*(.*?)\*\*/${bold_on}$1${bold_off}/g;
  $line =~ s://(.*?)//:${italic_on}$1$[italic_off}:g;
  $line =~ s/__(.*?)__/${underline_on}$1${underline_off}/g;
  print $line;
}
