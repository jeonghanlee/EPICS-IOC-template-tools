#!/usr/bin/env perl
use strict;
use warnings;

use Fcntl qw(:DEFAULT);
use File::Basename qw(basename dirname);
use File::Path qw(make_path);
use File::Temp qw(tempfile);
use Getopt::Long qw(GetOptionsFromArray);
use IO::Handle;
use Pod::Usage qw(pod2usage);
use POSIX ();
use Socket qw(AF_INET IPPROTO_TCP SOCK_STREAM SOL_SOCKET SO_REUSEADDR inet_aton pack_sockaddr_in unpack_sockaddr_in);
use Time::HiRes qw(time);

sub sync_directory {
    my ($dir) = @_;
    sysopen(my $dh, $dir, O_RDONLY | O_DIRECTORY) or die "$dir: $!\n";
    IO::Handle::sync($dh) or die "$dir: sync: $!\n";
    close($dh) or die "$dir: $!\n";
    return;
}

sub atomic_write {
    my ($path, $data, $mode) = @_;
    my $dir = dirname($path);
    make_path($dir) unless -d $dir;
    my ($fh, $tmp) = tempfile('.' . basename($path) . '.XXXXXX', DIR => $dir);
    my $done = eval {
        binmode($fh) or die "$tmp: $!\n";
        print {$fh} $data or die "$tmp: $!\n";
        $fh->flush or die "$tmp: $!\n";
        chmod($mode, $fh) or die "$tmp: $!\n";
        $fh->sync or die "$tmp: $!\n";
        close($fh) or die "$tmp: $!\n";
        rename($tmp, $path) or die "$path: $!\n";
        sync_directory($dir);
        1;
    };
    if (!$done) {
        my $error = $@;
        # Best-effort cleanup while another error is already being raised.
        unlink $tmp;
        die $error;
    }
    return;
}

sub write_all {
    my ($fh, $path, $buf) = @_;
    my $total = length($buf);
    my $offset = 0;
    while ($offset < $total) {
        my $written = syswrite($fh, $buf, $total - $offset, $offset);
        if (!defined $written) {
            next if $! == POSIX::EINTR();
            die "$path: syswrite: $!\n";
        }
        $offset += $written;
    }
    return;
}

sub main {
    my (@argv) = @_;
    my $host = '127.0.0.1';
    my $port;
    my $out_file;
    my $ready_file;
    my $pid_file;
    my $timeout = 60;
    my $help = 0;

    GetOptionsFromArray(
        \@argv,
        'host=s'       => \$host,
        'port=i'       => \$port,
        'out-file=s'   => \$out_file,
        'ready-file=s' => \$ready_file,
        'pid-file=s'   => \$pid_file,
        'timeout=f'    => \$timeout,
        'help|h'       => \$help,
    ) or die "invalid options\n";

    if ($help) {
        pod2usage(-exitval => 0, -verbose => 1, -output => \*STDOUT);
        return 0;
    }
    die "unexpected positional arguments\n" if @argv;
    defined $port && $port >= 0 && $port <= 65535 or die "--port must be an integer in 0..65535\n";
    defined $out_file && $out_file ne '' or die "--out-file is required\n";
    defined $ready_file && $ready_file ne '' or die "--ready-file is required\n";
    $timeout > 0 or die "--timeout must be positive\n";

    my $addr = inet_aton($host);
    defined $addr or die "cannot resolve host: $host\n";

    make_path(dirname($out_file)) unless -d dirname($out_file);
    open(my $out_fh, '>:raw', $out_file) or die "$out_file: $!\n";

    socket(my $server, AF_INET, SOCK_STREAM, IPPROTO_TCP) or die "socket: $!\n";
    setsockopt($server, SOL_SOCKET, SO_REUSEADDR, pack('l', 1)) or die "setsockopt: $!\n";
    bind($server, pack_sockaddr_in($port, $addr)) or die "bind($host:$port): $!\n";
    listen($server, 16) or die "listen: $!\n";

    my $sockname = getsockname($server);
    defined $sockname or die "getsockname: $!\n";
    my ($bound_port) = unpack_sockaddr_in($sockname);

    my $stop_requested = 0;
    local $SIG{INT} = sub { $stop_requested = 1 };
    local $SIG{TERM} = sub { $stop_requested = 1 };

    if (defined $pid_file && $pid_file ne '') {
        atomic_write($pid_file, "$$\n", 0644);
    }
    atomic_write($ready_file, "$bound_port\n", 0644);

    my %clients;
    my $server_fd = fileno($server);
    my $deadline = time() + $timeout;

    while (!$stop_requested && time() < $deadline) {
        my $rin = '';
        vec($rin, $server_fd, 1) = 1;
        for my $cfd (keys %clients) {
            vec($rin, $cfd, 1) = 1;
        }
        my $remaining = $deadline - time();
        my $wait_sec = $remaining < 0.1 ? ($remaining > 0 ? $remaining : 0) : 0.1;
        my $nfound = select(my $rout = $rin, undef, undef, $wait_sec);
        if ($nfound < 0) {
            next if $! == POSIX::EINTR();
            die "select: $!\n";
        }
        next if $nfound == 0;

        if (vec($rout, $server_fd, 1)) {
            if (accept(my $client, $server)) {
                binmode($client);
                my $cfd = fileno($client);
                $clients{$cfd} = $client if defined $cfd;
            }
        }
        for my $cfd (sort { $a <=> $b } keys %clients) {
            next unless vec($rout, $cfd, 1);
            my $client = $clients{$cfd};
            my $buf = '';
            my $nread = sysread($client, $buf, 8192);
            if (!defined $nread) {
                next if $! == POSIX::EINTR();
                close($client);
                delete $clients{$cfd};
            } elsif ($nread == 0) {
                close($client);
                delete $clients{$cfd};
            } else {
                write_all($out_fh, $out_file, $buf);
            }
        }
    }

    # Drain any buffered bytes already queued on accepted sockets before closing.
    for my $cfd (sort { $a <=> $b } keys %clients) {
        my $client = $clients{$cfd};
        my $rin = '';
        vec($rin, $cfd, 1) = 1;
        while (1) {
            my $rout = $rin;
            last unless select($rout, undef, undef, 0) > 0 && vec($rout, $cfd, 1);
            my $buf = '';
            my $nread = sysread($client, $buf, 8192);
            last if !defined($nread) || $nread == 0;
            write_all($out_fh, $out_file, $buf);
        }
        close($client);
    }

    close($server) or die "close server socket: $!\n";
    IO::Handle::sync($out_fh) or die "$out_file: sync: $!\n";
    close($out_fh) or die "$out_file: $!\n";
    return 0;
}

my $status;
eval {
    $status = main(@ARGV);
    defined $status or die "internal error: main returned no exit status\n";
    1;
} or do {
    my $error = $@;
    print STDERR "m2-tcp-receiver.pl: $error";
    $status = 2;
};
exit $status;

__END__

=head1 NAME

m2-tcp-receiver.pl - Bounded local TCP stream receiver for M2 logging tests

=head1 SYNOPSIS

  m2-tcp-receiver.pl --port <port> --out-file <file> --ready-file <file>
      [--host 127.0.0.1] [--pid-file <file>] [--timeout 60]

  m2-tcp-receiver.pl --help

=head1 DESCRIPTION

Listens on a loopback TCP endpoint, publishes the bound port atomically after
listen succeeds, records raw received bytes without transformation, and exits
cleanly on INT, TERM, or timeout.

=head1 OPTIONS

=over 4

=item B<--host> I<address>

Loopback bind address (default C<127.0.0.1>).

=item B<--port> I<port>

TCP port to bind (C<0..65535>).

=item B<--out-file> I<path>

Destination file receiving raw TCP stream bytes.

=item B<--ready-file> I<path>

File atomically written once the listening socket is ready.

=item B<--pid-file> I<path>

Optional file receiving the listener process ID.

=item B<--timeout> I<seconds>

Maximum lifetime in seconds before automatic clean stop (default C<60>).

=item B<--help>, B<-h>

Prints usage documentation and exits 0.

=back

=head1 EXIT STATUS

=over 4

=item B<0>

Listener started, captured incoming bytes until stop or timeout, and flushed
the output file cleanly.

=item B<2>

Usage error, bind failure, or filesystem I/O error.

=back

=cut
