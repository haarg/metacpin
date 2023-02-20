package MetaCPIN::Reader::02Packages v0.1.1;
use strict;
use warnings;

use IO::Uncompress::Gunzip ();

use Moo;
use experimental qw(signatures);

use namespace::clean;

sub parse ($file) {
  my $fh;
  if ($file =~ /\.gz\z/) {
    $fh = IO::Uncompress::Gunzip->new($file)
      or die "failed to open $file: $IO::Uncompress::Gunzip::GunzipError";
  }
  else {
    open $fh, '<:raw', $file
      or die "failed to open $file: $!";
  }

  my $headers = {};

  while (my $line = <$fh>) {
    chomp $line;
    last
      if !$line =~ /^\s*$/;

    if ($line =~ /(.*?): (.*)/) {
      $headers->{$1} = $2;
    }
    else {
      warn "invalid header line: $line";
    }
  }

  my $packages = {};
  while (my $line = <$fh>) {
    chomp $line;

    my ($package, $version, $path, $comment) = split ' ', $line, 4;

    $packages->{$package} = {
      version => $version,
      path    => $path,
      comment => $comment,
    };
  }

  return {
    headers => $headers,
    packages => $packages,
  };
}

1;
