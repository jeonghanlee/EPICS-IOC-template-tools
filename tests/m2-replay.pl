#!/usr/bin/env perl
use strict;
use warnings;

use Cwd qw(abs_path getcwd);
use Fcntl qw(:DEFAULT :mode);
use File::Basename qw(basename dirname);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempfile);
use Getopt::Long qw(GetOptionsFromArray);
use IO::Handle;
use JSON::PP;
use Pod::Usage qw(pod2usage);
use POSIX ();

my $HASH_COMMAND = 'sha256sum';
my $EXEC_FAILURE = 127;
my @REQUIRED_DEPS = qw(bash perl sha256sum grep awk sed stat cmp sort);
my %VALID_SUITES = map { $_ => 1 } qw(
    dual-startup
    live-runtime
    inventory-env
    defaults-paths-hooks
    services
    protocols-autosave
    faults
);
my @TOOL_FILES = (
    'tests/test-trash.bash',
    'tests/m2-evaluate.bash',
    'tests/m2-evidence.bash',
    'tests/m2-driver-lib.bash',
    'tests/m2-macro-contract.tsv',
    'tests/m2-tcp-receiver.pl',
    'tests/test-dual-startup.bash',
    'tests/generation-matrix.bash',
    'tests/m2-generation-cases.tsv',
    'tests/m2-cli-cases.tsv',
    'tests/test-live-runtime.bash',
    'tests/test-inventory-env.bash',
    'tests/test-defaults-paths-hooks.bash',
    'tests/test-services.bash',
    'tests/test-protocols-autosave.bash',
    'tests/test-faults.bash',
    'tests/m2-replay.pl',
    'tests/fixtures/dual-startup.db',
    'tests/fixtures/runtime.db',
    'tests/fixtures/runtime.json',
    'tests/fixtures/autosave-passes.db',
    'tests/fixtures/autosave-observer.dbd',
    'tests/fixtures/ioclog-observer.c',
    'tests/fixtures/ioclog-observer.dbd',
);

sub escape_field {
    my ($value) = @_;
    $value =~ s/%/%25/g;
    $value =~ s/\t/%09/g;
    $value =~ s/\r/%0d/g;
    $value =~ s/\n/%0a/g;
    return $value;
}

sub unescape_field {
    my ($value) = @_;
    $value =~ s/%([0-9a-fA-F]{2})/chr(hex($1))/ge;
    return $value;
}

sub read_bytes {
    my ($path) = @_;
    open(my $fh, '<:raw', $path) or die "$path: $!\n";
    my $data = do { local $/; <$fh> };
    close($fh) or die "$path: $!\n";
    my @st = lstat($path);
    @st or die "$path: $!\n";
    my $mode = $st[2] & 07777;
    return (defined $data ? $data : '', $mode);
}

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

sub exec_or_exit {
    my (@command) = @_;
    {
        no warnings 'exec';
        exec { $command[0] } @command;
    }
    POSIX::_exit($EXEC_FAILURE);
}

sub wait_child {
    my ($pid) = @_;
    my $waited;
    do { $waited = waitpid($pid, 0) } while ($waited == -1 && $! == POSIX::EINTR());
    return $?;
}

sub run_capture {
    my (@command) = @_;
    my $pid = open(my $out, '-|');
    defined $pid or die "$command[0]: fork: $!\n";
    exec_or_exit(@command) if !$pid;
    my $text;
    my $done = eval {
        binmode($out);
        $text = do { local $/; <$out> };
        1;
    };
    if (!$done) {
        my $error = $@;
        kill('TERM', $pid);
        close($out);
        die $error;
    }
    close($out);
    die "$command[0]: terminated by signal " . ($? & 127) . "\n" if $? & 127;
    return ($? >> 8, defined $text ? $text : '');
}

sub run_command_full {
    my ($argv_ref, $cwd, $env_ref, $stdout_path, $stderr_path) = @_;
    my @command = @{$argv_ref};
    my $start_utc = POSIX::strftime('%Y-%m-%dT%H:%M:%SZ', gmtime());
    my $start_mono = read_monotonic();
    my $pid = fork();
    defined $pid or die "$command[0]: fork: $!\n";
    if (!$pid) {
        $SIG{INT} = 'DEFAULT';
        $SIG{QUIT} = 'DEFAULT';
        $SIG{TERM} = 'DEFAULT';
        if (defined $cwd) {
            chdir($cwd) or POSIX::_exit(126);
        }
        if (defined $env_ref) {
            for my $key (sort { $a cmp $b } keys %{$env_ref}) {
                if (defined $env_ref->{$key}) {
                    $ENV{$key} = $env_ref->{$key};
                } else {
                    delete $ENV{$key};
                }
            }
        }
        open(STDIN, '<:raw', '/dev/null') or POSIX::_exit(126);
        open(STDOUT, '>:raw', $stdout_path) or POSIX::_exit(126);
        open(STDERR, '>:raw', $stderr_path) or POSIX::_exit(126);
        exec_or_exit(@command);
    }
    my $raw_wait = wait_child($pid);
    my $end_mono = read_monotonic();
    my $end_utc = POSIX::strftime('%Y-%m-%dT%H:%M:%SZ', gmtime());
    my $sig = $raw_wait & 127;
    my $code = $sig ? (128 + $sig) : ($raw_wait >> 8);
    return {
        native_returncode => $code,
        signal            => $sig,
        start_utc         => $start_utc,
        end_utc           => $end_utc,
        start_monotonic   => $start_mono,
        end_monotonic     => $end_mono,
    };
}

sub read_monotonic {
    open(my $fh, '<:raw', '/proc/uptime') or die "/proc/uptime: $!\n";
    my $line = <$fh>;
    close($fh) or die "/proc/uptime: $!\n";
    defined $line or die "/proc/uptime: empty\n";
    my ($up) = $line =~ /^([0-9.]+)/;
    defined $up or die "/proc/uptime: malformed\n";
    return $up;
}

sub sha256_command {
    my ($path) = @_;
    my ($status, $text) = run_capture($HASH_COMMAND, '--', $path);
    die "$HASH_COMMAND: exit $status\n" if $status;
    my ($hex) = $text =~ /^\\?([0-9a-f]{64})\s/ or die "$HASH_COMMAND: bad output\n";
    return $hex;
}

sub sha256_file {
    my ($path) = @_;
    if (!$ENV{M2_FORCE_SHA256_CMD} && eval { require Digest::SHA; 1 }) {
        my $sha = Digest::SHA->new(256);
        open(my $fh, '<:raw', $path) or die "$path: $!\n";
        $sha->addfile($fh);
        close($fh) or die "$path: $!\n";
        return $sha->hexdigest;
    }
    return sha256_command($path);
}

sub resolve_executable {
    my ($name) = @_;
    my $raw_path = defined $ENV{PATH} ? $ENV{PATH} : '';
    for my $dir (split /:/, $raw_path) {
        next if $dir eq '';
        my $candidate = File::Spec->catfile($dir, $name);
        if (-f $candidate && -x $candidate) {
            my $real = abs_path($candidate);
            defined $real or die "$candidate: cannot resolve path\n";
            return $real;
        }
    }
    die "required executable not found in PATH: $name\n";
}

sub validate_relative_symlink {
    my ($root_abs, $link_path, $target) = @_;
    die "$link_path: empty symlink target\n" if $target eq '';
    die "$link_path: absolute symlink target is prohibited: $target\n"
        if File::Spec->file_name_is_absolute($target);
    my $link_dir = dirname($link_path);
    my $combined = File::Spec->catfile($link_dir, $target);
    my @parts = File::Spec->splitdir($combined);
    my @norm;
    for my $part (@parts) {
        next if $part eq '.' || $part eq '';
        if ($part eq '..') {
            pop @norm;
        } else {
            push @norm, $part;
        }
    }
    my $norm_path = '/' . join('/', @norm);
    my $prefix = $root_abs eq '/' ? '/' : "$root_abs/";
    die "$link_path: symlink escapes root ($target)\n"
        unless $norm_path eq $root_abs || index($norm_path, $prefix) == 0;
    my @target_st = lstat($combined);
    @target_st or die "$link_path: dangling symlink target ($target)\n";
    return;
}

sub scan_tree {
    my ($root_dir, $prefix) = @_;
    my $root_abs = abs_path($root_dir);
    defined $root_abs or die "$root_dir: cannot resolve root\n";
    my @records;
    my $walk;
    $walk = sub {
        my ($cur_abs, $cur_rel) = @_;
        opendir(my $dh, $cur_abs) or die "$cur_abs: $!\n";
        my @names = sort { $a cmp $b } grep { $_ ne '.' && $_ ne '..' } readdir($dh);
        closedir($dh) or die "$cur_abs: $!\n";
        for my $name (@names) {
            my $child_abs = "$cur_abs/$name";
            my $child_rel = $cur_rel eq '' ? $name : "$cur_rel/$name";
            my $full_rel = $prefix eq '' ? $child_rel : "$prefix/$child_rel";
            my @st = lstat($child_abs);
            @st or die "$child_abs: $!\n";
            my $mode = $st[2];
            if (S_ISLNK($mode)) {
                my $target = readlink($child_abs);
                defined $target or die "$child_abs: readlink: $!\n";
                validate_relative_symlink($root_abs, $child_abs, $target);
                push @records, {
                    relpath => $full_rel,
                    kind    => 'symlink',
                    mode    => '0777',
                    size    => length($target),
                    value   => $target,
                };
            } elsif (S_ISDIR($mode)) {
                push @records, {
                    relpath => $full_rel,
                    kind    => 'dir',
                    mode    => sprintf('%04o', $mode & 07777),
                    size    => 0,
                    value   => '-',
                };
                $walk->($child_abs, $child_rel);
            } elsif (S_ISREG($mode)) {
                push @records, {
                    relpath => $full_rel,
                    kind    => 'file',
                    mode    => sprintf('%04o', $mode & 07777),
                    size    => $st[7],
                    value   => sha256_file($child_abs),
                };
            } else {
                die "$child_abs: unsupported special file in bundle\n";
            }
        }
    };
    $walk->($root_abs, '');
    @records = sort { $a->{relpath} cmp $b->{relpath} } @records;
    return \@records;
}

sub copy_tree {
    my ($src_dir, $dst_dir) = @_;
    my $src_abs = abs_path($src_dir);
    defined $src_abs or die "$src_dir: cannot resolve source directory\n";
    my @src_st = lstat($src_abs);
    @src_st && S_ISDIR($src_st[2]) or die "$src_dir: not a directory\n";
    mkdir($dst_dir, 0755) or die "$dst_dir: $!\n";
    my $walk;
    $walk = sub {
        my ($cur_src, $cur_dst) = @_;
        opendir(my $dh, $cur_src) or die "$cur_src: $!\n";
        my @names = sort { $a cmp $b } grep { $_ ne '.' && $_ ne '..' } readdir($dh);
        closedir($dh) or die "$cur_src: $!\n";
        for my $name (@names) {
            my $s = "$cur_src/$name";
            my $d = "$cur_dst/$name";
            my @st = lstat($s);
            @st or die "$s: $!\n";
            my $mode = $st[2];
            if (S_ISLNK($mode)) {
                my $target = readlink($s);
                defined $target or die "$s: readlink: $!\n";
                validate_relative_symlink($src_abs, $s, $target);
                symlink($target, $d) or die "$d: symlink: $!\n";
            } elsif (S_ISDIR($mode)) {
                mkdir($d, 0755) or die "$d: $!\n";
                $walk->($s, $d);
                chmod($mode & 07777, $d) or die "$d: $!\n";
            } elsif (S_ISREG($mode)) {
                my ($bytes, $fmode) = read_bytes($s);
                atomic_write($d, $bytes, $fmode);
            } else {
                die "$s: unsupported special file during copy\n";
            }
        }
    };
    $walk->($src_abs, $dst_dir);
    chmod($src_st[2] & 07777, $dst_dir) or die "$dst_dir: $!\n";
    return;
}

sub format_manifest {
    my ($records_ref) = @_;
    my @lines;
    for my $rec (@{$records_ref}) {
        push @lines, join("\t",
            escape_field($rec->{relpath}),
            $rec->{kind},
            $rec->{mode},
            $rec->{size},
            escape_field($rec->{value}),
        ) . "\n";
    }
    return join('', @lines);
}

sub parse_manifest {
    my ($path) = @_;
    my ($raw) = read_bytes($path);
    my @lines = split /\n/, $raw, -1;
    pop @lines if @lines && $lines[-1] eq '';
    my @records;
    my %seen;
    for my $line (@lines) {
        $line =~ s/\r$//;
        my @parts = split /\t/, $line, -1;
        die "$path: malformed manifest row\n" unless @parts == 5;
        my $relpath = unescape_field($parts[0]);
        die "$path: duplicate manifest member: $relpath\n" if $seen{$relpath}++;
        push @records, {
            relpath => $relpath,
            kind    => $parts[1],
            mode    => $parts[2],
            size    => $parts[3],
            value   => unescape_field($parts[4]),
        };
    }
    return \@records;
}

sub parse_result_file {
    my ($path) = @_;
    my ($raw) = read_bytes($path);
    my %result = (
        passed   => undef,
        failed   => undef,
        verdict  => undef,
        exit_rc  => undef,
        native   => undef,
    );
    for my $line (split /\n/, $raw) {
        $line =~ s/\r$//;
        if ($line =~ /^Passed:\s*(\d+)$/) {
            $result{passed} = int($1);
        } elsif ($line =~ /^Failed:\s*(\d+)$/) {
            $result{failed} = int($1);
        } elsif ($line =~ /^Verdict:\s*(Passed|Failed|Incomplete)$/) {
            $result{verdict} = $1;
        } elsif ($line =~ /^Exit status:\s*(\d+)$/) {
            $result{exit_rc} = int($1);
        } elsif ($line =~ /^Native status:\s*(\d+)$/) {
            $result{native} = int($1);
        }
    }
    defined $result{passed} && defined $result{failed} && defined $result{verdict}
        or die "$path: incomplete result fields\n";
    if (!defined $result{exit_rc}) {
        if ($result{verdict} eq 'Failed') {
            $result{exit_rc} = (defined $result{native} && $result{native} != 0) ? $result{native} : 1;
        } elsif ($result{verdict} eq 'Incomplete') {
            $result{exit_rc} = (defined $result{native} && $result{native} != 0) ? $result{native} : 2;
        } else {
            $result{exit_rc} = defined $result{native} ? $result{native} : 0;
        }
    }
    return \%result;
}

sub expected_eval_status {
    my ($verdict) = @_;
    return 0 if $verdict eq 'Passed';
    return 1 if $verdict eq 'Failed';
    return 2;
}

sub parse_assertions_file {
    my ($path) = @_;
    return [] unless -f $path;
    my ($raw) = read_bytes($path);
    my @rows;
    for my $line (split /\n/, $raw) {
        $line =~ s/\r$//;
        next if $line eq '';
        my @cols = split /\t/, $line, -1;
        die "$path: malformed assertion row\n" unless @cols == 3;
        push @rows, \@cols;
    }
    return \@rows;
}

sub helper_self_sha256 {
    my $self = abs_path($0);
    defined $self && -f $self or die "cannot resolve m2-replay.pl path\n";
    return sha256_file($self);
}

sub probe_dependencies {
    my ($probe_dir) = @_;
    make_path($probe_dir);
    my @deps;
    for my $name (@REQUIRED_DEPS) {
        my $resolved = resolve_executable($name);
        my $bin_sha = sha256_file($resolved);
        my $out_file = "$probe_dir/$name.stdout";
        my $err_file = "$probe_dir/$name.stderr";
        my $outcome = run_command_full([$resolved, '--version'], undef, undef, $out_file, $err_file);
        my $status_text = "$outcome->{native_returncode}\n";
        atomic_write("$probe_dir/$name.status", $status_text, 0644);
        push @deps, {
            name       => $name,
            path       => $resolved,
            sha256     => $bin_sha,
            probe_rc   => $outcome->{native_returncode},
            stdout_sha => sha256_file($out_file),
        };
    }
    return \@deps;
}

sub ensure_fresh_dir {
    my ($dir, $label) = @_;
    defined $dir && $dir ne '' or die "missing required $label directory\n";
    die "$label directory already exists: $dir\n" if -e $dir || -l $dir;
    my $parent = dirname($dir);
    make_path($parent) unless -d $parent;
    mkdir($dir, 0755) or die "$dir: $!\n";
    return abs_path($dir);
}

sub cmd_freeze {
    my ($args_ref) = @_;
    my ($suite, $run_dir, $source_root, $bundle_dir, $pin_dir);
    GetOptionsFromArray(
        $args_ref,
        'suite=s'       => \$suite,
        'run-dir=s'     => \$run_dir,
        'source-root=s' => \$source_root,
        'bundle-dir=s'  => \$bundle_dir,
        'pin-dir=s'     => \$pin_dir,
    ) or die "freeze: invalid options\n";
    die "freeze: unexpected positional arguments\n" if @{$args_ref};
    defined $suite && $VALID_SUITES{$suite}
        or die "freeze: --suite must name a supported M2 suite\n";
    defined $run_dir && -d $run_dir or die "freeze: --run-dir must name an existing directory\n";
    defined $source_root && -d $source_root or die "freeze: --source-root must name an existing directory\n";

    my $run_abs = abs_path($run_dir);
    my $src_abs = abs_path($source_root);
    my $run_base = basename($run_abs);
    -f "$run_abs/result.txt" or die "freeze: $run_abs/result.txt is missing\n";
    my $parsed_result = parse_result_file("$run_abs/result.txt");

    my $bundle_abs = ensure_fresh_dir($bundle_dir, 'bundle');
    my $pin_abs = ensure_fresh_dir($pin_dir, 'pin');

    mkdir("$bundle_abs/input", 0755) or die "$bundle_abs/input: $!\n";
    copy_tree($run_abs, "$bundle_abs/input/$run_base");

    mkdir("$bundle_abs/tools", 0755) or die "$bundle_abs/tools: $!\n";
    for my $rel (@TOOL_FILES) {
        my $src_file = "$src_abs/$rel";
        -f $src_file or die "freeze: missing shipped tool file: $src_file\n";
        my $dst_file = "$bundle_abs/tools/$rel";
        make_path(dirname($dst_file));
        my ($bytes, $mode) = read_bytes($src_file);
        atomic_write($dst_file, $bytes, $mode);
    }
    symlink('tests/m2-evaluate.bash', "$bundle_abs/tools/active-evaluator")
        or die "$bundle_abs/tools/active-evaluator: symlink: $!\n";

    mkdir("$bundle_abs/recorded", 0755) or die "$bundle_abs/recorded: $!\n";
    my ($res_bytes, $res_mode) = read_bytes("$run_abs/result.txt");
    atomic_write("$bundle_abs/recorded/result.txt", $res_bytes, $res_mode);
    my $has_assertions = 0;
    if (-f "$run_abs/assertions.tsv") {
        my ($as_bytes, $as_mode) = read_bytes("$run_abs/assertions.tsv");
        atomic_write("$bundle_abs/recorded/assertions.tsv", $as_bytes, $as_mode);
        $has_assertions = 1;
    } else {
        atomic_write("$bundle_abs/recorded/assertions.tsv", '', 0644);
    }

    my $deps_ref = probe_dependencies("$bundle_abs/recorded/dependencies");
    my $self_sha = helper_self_sha256();
    my $receipt = {
        suite                => $suite,
        run_basename         => $run_base,
        recorded_verdict     => $parsed_result->{verdict},
        recorded_passed      => $parsed_result->{passed},
        recorded_failed      => $parsed_result->{failed},
        recorded_exit_status => $parsed_result->{exit_rc},
        expected_eval_status => expected_eval_status($parsed_result->{verdict}),
        has_assertions       => $has_assertions ? JSON::PP::true : JSON::PP::false,
        helper_sha256        => $self_sha,
        dependencies         => $deps_ref,
    };
    my $json = JSON::PP->new->canonical->pretty->indent_length(2);
    atomic_write("$bundle_abs/recorded/receipt.json", $json->encode($receipt), 0644);

    my @all_records;
    for my $sub (qw(input tools recorded)) {
        my @st = lstat("$bundle_abs/$sub");
        push @all_records, {
            relpath => $sub,
            kind    => 'dir',
            mode    => sprintf('%04o', $st[2] & 07777),
            size    => 0,
            value   => '-',
        };
        my $sub_recs = scan_tree("$bundle_abs/$sub", $sub);
        push @all_records, @{$sub_recs};
    }
    @all_records = sort { $a->{relpath} cmp $b->{relpath} } @all_records;
    my $manifest_text = format_manifest(\@all_records);
    atomic_write("$bundle_abs/manifest.tsv", $manifest_text, 0644);
    my $manifest_sha = sha256_file("$bundle_abs/manifest.tsv");

    atomic_write("$pin_abs/manifest.sha256", "$manifest_sha\n", 0644);
    atomic_write("$pin_abs/members.tsv", $manifest_text, 0644);
    my @dep_lines = ("helper\t-\t$self_sha\t0\t-\n");
    for my $dep (@{$deps_ref}) {
        push @dep_lines, join("\t",
            $dep->{name},
            escape_field($dep->{path}),
            $dep->{sha256},
            $dep->{probe_rc},
            $dep->{stdout_sha},
        ) . "\n";
    }
    atomic_write("$pin_abs/dependencies.tsv", join('', @dep_lines), 0644);

    print "Operation verdict: Passed\nManifest-SHA256: $manifest_sha\n";
    return 0;
}

sub load_pin_dependencies {
    my ($path) = @_;
    my ($raw) = read_bytes($path);
    my %deps;
    for my $line (split /\n/, $raw) {
        $line =~ s/\r$//;
        next if $line eq '';
        my @cols = split /\t/, $line, -1;
        die "$path: malformed dependency row\n" unless @cols == 5;
        $deps{$cols[0]} = {
            name       => $cols[0],
            path       => unescape_field($cols[1]),
            sha256     => $cols[2],
            probe_rc   => int($cols[3]),
            stdout_sha => $cols[4],
        };
    }
    return \%deps;
}

sub verify_records_equal {
    my ($expected_ref, $actual_ref, $context) = @_;
    my @exp = @{$expected_ref};
    my @act = @{$actual_ref};
    my %exp_map = map { $_->{relpath} => $_ } @exp;
    my %act_map = map { $_->{relpath} => $_ } @act;
    for my $rel (sort { $a cmp $b } keys %exp_map) {
        exists $act_map{$rel} or die "$context: missing member: $rel\n";
    }
    for my $rel (sort { $a cmp $b } keys %act_map) {
        exists $exp_map{$rel} or die "$context: extra member: $rel\n";
    }
    die "$context: member count mismatch\n" unless scalar(@exp) == scalar(@act);
    for my $i (0 .. $#exp) {
        my $e = $exp[$i];
        my $a = $act[$i];
        die "$context: member order mismatch at $e->{relpath}\n" unless $e->{relpath} eq $a->{relpath};
        die "$context: kind mismatch at $e->{relpath} ($e->{kind} vs $a->{kind})\n" unless $e->{kind} eq $a->{kind};
        die "$context: mode mismatch at $e->{relpath} ($e->{mode} vs $a->{mode})\n" unless $e->{mode} eq $a->{mode};
        die "$context: size mismatch at $e->{relpath} ($e->{size} vs $a->{size})\n" unless $e->{size} == $a->{size};
        die "$context: content/target mismatch at $e->{relpath}\n" unless $e->{value} eq $a->{value};
    }
    return;
}

sub verify_bundle_against_pin {
    my ($bundle_dir, $pin_dir, $run_probes_dir) = @_;
    defined $bundle_dir && -d $bundle_dir or die "verify: invalid bundle directory\n";
    defined $pin_dir && -d $pin_dir or die "verify: invalid pin directory\n";
    my $bundle_abs = abs_path($bundle_dir);
    my $pin_abs = abs_path($pin_dir);

    my ($pin_sha_raw) = read_bytes("$pin_abs/manifest.sha256");
    my ($pinned_sha) = $pin_sha_raw =~ /^([0-9a-f]{64})\s*$/;
    defined $pinned_sha or die "verify: invalid manifest.sha256 in pin directory\n";

    my $pinned_members = parse_manifest("$pin_abs/members.tsv");
    my $pinned_deps = load_pin_dependencies("$pin_abs/dependencies.tsv");

    exists $pinned_deps->{helper} or die "verify: helper entry missing in dependencies.tsv\n";
    my $self_sha = helper_self_sha256();
    die "verify: helper sha256 mismatch\n" unless $self_sha eq $pinned_deps->{helper}{sha256};

    for my $name (@REQUIRED_DEPS) {
        exists $pinned_deps->{$name} or die "verify: missing pinned dependency $name\n";
        my $resolved = resolve_executable($name);
        my $cur_sha = sha256_file($resolved);
        die "verify: dependency sha256 mismatch for $name\n"
            unless $cur_sha eq $pinned_deps->{$name}{sha256};
    }

    opendir(my $top_dh, $bundle_abs) or die "$bundle_abs: $!\n";
    my @top_entries = sort { $a cmp $b } grep { $_ ne '.' && $_ ne '..' } readdir($top_dh);
    closedir($top_dh) or die "$bundle_abs: $!\n";
    my %allowed_top = map { $_ => 1 } qw(input manifest.tsv recorded tools);
    for my $entry (@top_entries) {
        die "verify: extra top-level bundle member: $entry\n" unless $allowed_top{$entry};
    }
    for my $req (qw(input manifest.tsv recorded tools)) {
        -e "$bundle_abs/$req" || -l "$bundle_abs/$req"
            or die "verify: missing top-level bundle member: $req\n";
    }

    my $candidate_manifest = parse_manifest("$bundle_abs/manifest.tsv");
    my $candidate_manifest_sha = sha256_file("$bundle_abs/manifest.tsv");
    die "verify: manifest.tsv sha256 does not match independent pin\n"
        unless $candidate_manifest_sha eq $pinned_sha;
    verify_records_equal($pinned_members, $candidate_manifest, 'verify-manifest');

    my @actual_records;
    for my $sub (qw(input tools recorded)) {
        my @st = lstat("$bundle_abs/$sub");
        @st && S_ISDIR($st[2]) or die "verify: $sub is not a directory\n";
        push @actual_records, {
            relpath => $sub,
            kind    => 'dir',
            mode    => sprintf('%04o', $st[2] & 07777),
            size    => 0,
            value   => '-',
        };
        my $sub_recs = scan_tree("$bundle_abs/$sub", $sub);
        push @actual_records, @{$sub_recs};
    }
    @actual_records = sort { $a->{relpath} cmp $b->{relpath} } @actual_records;
    verify_records_equal($pinned_members, \@actual_records, 'verify-disk');

    if (defined $run_probes_dir) {
        my $live_probes = probe_dependencies($run_probes_dir);
        for my $probe (@{$live_probes}) {
            my $pin = $pinned_deps->{$probe->{name}};
            die "verify: probe status mismatch for $probe->{name}\n"
                unless $probe->{probe_rc} == $pin->{probe_rc};
            die "verify: probe output mismatch for $probe->{name}\n"
                unless $probe->{stdout_sha} eq $pin->{stdout_sha};
        }
    }

    my ($receipt_raw) = read_bytes("$bundle_abs/recorded/receipt.json");
    my $receipt;
    my $decoded_ok = eval { $receipt = JSON::PP->new->decode($receipt_raw); 1 };
    $decoded_ok && ref($receipt) eq 'HASH' or die "verify: malformed receipt.json\n";
    for my $field (qw(suite run_basename recorded_verdict recorded_passed recorded_failed expected_eval_status)) {
        exists $receipt->{$field} && defined $receipt->{$field} && !ref($receipt->{$field})
            or die "verify: missing scalar field $field in receipt.json\n";
    }
    return ($bundle_abs, $pinned_members, $pinned_deps, $receipt);
}

sub cmd_verify {
    my ($args_ref) = @_;
    my ($bundle_dir, $pin_dir, $output_dir);
    GetOptionsFromArray(
        $args_ref,
        'bundle-dir=s' => \$bundle_dir,
        'pin-dir=s'    => \$pin_dir,
        'output-dir=s' => \$output_dir,
    ) or die "verify: invalid options\n";
    die "verify: unexpected positional arguments\n" if @{$args_ref};
    my $out_abs;
    if (defined $output_dir && $output_dir ne '') {
        $out_abs = ensure_fresh_dir($output_dir, 'verify-output');
    }
    verify_bundle_against_pin($bundle_dir, $pin_dir, undef);
    if (defined $out_abs) {
        atomic_write("$out_abs/verify-result.txt", "Operation verdict: Passed\n", 0644);
    }
    print "Operation verdict: Passed\n";
    return 0;
}

sub write_replay_incomplete {
    my ($out_abs, $reason) = @_;
    if (defined $out_abs && -d $out_abs) {
        my $text = "Operation verdict: Incomplete\nReason: $reason";
        $text .= "\n" unless $text =~ /\n\z/;
        eval { atomic_write("$out_abs/replay-result.txt", $text, 0644); 1 };
    }
    return;
}

sub cmd_replay {
    my ($args_ref) = @_;
    my ($bundle_dir, $pin_dir, $output_dir);
    GetOptionsFromArray(
        $args_ref,
        'bundle-dir=s' => \$bundle_dir,
        'pin-dir=s'    => \$pin_dir,
        'output-dir=s' => \$output_dir,
    ) or die "replay: invalid options\n";
    die "replay: unexpected positional arguments\n" if @{$args_ref};
    my $out_abs = ensure_fresh_dir($output_dir, 'replay-output');

    my ($bundle_abs, $pinned_members, $pinned_deps, $receipt);
    my $verified = eval {
        ($bundle_abs, $pinned_members, $pinned_deps, $receipt) =
            verify_bundle_against_pin($bundle_dir, $pin_dir, "$out_abs/dependencies");
        1;
    };
    if (!$verified) {
        my $err = $@;
        write_replay_incomplete($out_abs, $err);
        die $err;
    }

    my $run_base = $receipt->{run_basename};
    my $suite = $receipt->{suite};
    mkdir("$out_abs/work", 0755) or die "$out_abs/work: $!\n";
    mkdir("$out_abs/work/input", 0755) or die "$out_abs/work/input: $!\n";
    mkdir("$out_abs/work/empty-cwd", 0755) or die "$out_abs/work/empty-cwd: $!\n";
    copy_tree("$bundle_abs/input/$run_base", "$out_abs/work/input/$run_base");
    copy_tree("$bundle_abs/tools", "$out_abs/work/tools");

    my $input_before = scan_tree("$out_abs/work/input/$run_base", '');
    my $tools_before = scan_tree("$out_abs/work/tools", '');

    my $rechecked = eval {
        verify_bundle_against_pin($bundle_abs, $pin_dir, undef);
        my $bundle_input_recs = scan_tree("$bundle_abs/input/$run_base", '');
        my $bundle_tools_recs = scan_tree("$bundle_abs/tools", '');
        verify_records_equal($bundle_input_recs, $input_before, 'prelaunch-input-copy');
        verify_records_equal($bundle_tools_recs, $tools_before, 'prelaunch-tools-copy');
        1;
    };
    if (!$rechecked) {
        my $err = $@;
        write_replay_incomplete($out_abs, $err);
        die $err;
    }

    my $bash_path = resolve_executable('bash');
    my $eval_link = "$out_abs/work/tools/active-evaluator";
    my $copied_run = "$out_abs/work/input/$run_base";
    my $eval_out = "$out_abs/evaluation";
    my $inv_log = "$out_abs/evaluator-invocations.tsv";
    my @argv = ($bash_path, $eval_link, $suite, $copied_run, '--out-dir', $eval_out);
    my $json = JSON::PP->new->canonical->pretty->indent_length(2);

    atomic_write(
        "$out_abs/command.running.json",
        $json->encode({
            argv => \@argv,
            cwd  => "$out_abs/work/empty-cwd",
        }),
        0644,
    );

    my $outcome = run_command_full(
        \@argv,
        "$out_abs/work/empty-cwd",
        {
            TEST_SOURCE_ROOT => "$out_abs/work/tools",
            M2_EVALUATOR_LOG => $inv_log,
        },
        "$out_abs/command.stdout",
        "$out_abs/command.stderr",
    );

    atomic_write(
        "$out_abs/command.json",
        $json->encode({
            argv              => \@argv,
            cwd               => "$out_abs/work/empty-cwd",
            native_returncode => $outcome->{native_returncode},
            signal            => $outcome->{signal},
            start_utc         => $outcome->{start_utc},
            end_utc           => $outcome->{end_utc},
            start_monotonic   => $outcome->{start_monotonic},
            end_monotonic     => $outcome->{end_monotonic},
        }),
        0644,
    );

    my $immutable = eval {
        verify_bundle_against_pin($bundle_abs, $pin_dir, undef);
        my $input_after = scan_tree("$out_abs/work/input/$run_base", '');
        my $tools_after = scan_tree("$out_abs/work/tools", '');
        verify_records_equal($input_before, $input_after, 'postreplay-input-immutable');
        verify_records_equal($tools_before, $tools_after, 'postreplay-tools-immutable');
        1;
    };
    if (!$immutable) {
        my $err = $@;
        write_replay_incomplete($out_abs, $err);
        die $err;
    }

    if (!-f "$eval_out/result.txt") {
        my $err = "replay: evaluator produced no result.txt\n";
        write_replay_incomplete($out_abs, $err);
        die $err;
    }

    my $replayed_res = parse_result_file("$eval_out/result.txt");
    my $recorded_rows = parse_assertions_file("$bundle_abs/recorded/assertions.tsv");
    my $replayed_rows = parse_assertions_file("$eval_out/assertions.tsv");

    my @mismatches;
    if ($outcome->{native_returncode} != int($receipt->{expected_eval_status})) {
        push @mismatches, "native_returncode ($outcome->{native_returncode} != $receipt->{expected_eval_status})";
    }
    if ($replayed_res->{verdict} ne $receipt->{recorded_verdict}) {
        push @mismatches, "verdict ($replayed_res->{verdict} != $receipt->{recorded_verdict})";
    }
    if ($replayed_res->{passed} != int($receipt->{recorded_passed})) {
        push @mismatches, "passed ($replayed_res->{passed} != $receipt->{recorded_passed})";
    }
    if ($replayed_res->{failed} != int($receipt->{recorded_failed})) {
        push @mismatches, "failed ($replayed_res->{failed} != $receipt->{recorded_failed})";
    }
    if (scalar(@{$replayed_rows}) != scalar(@{$recorded_rows})) {
        push @mismatches, 'assertion_count (' . scalar(@{$replayed_rows}) . ' != ' . scalar(@{$recorded_rows}) . ')';
    } else {
        for my $i (0 .. $#{$recorded_rows}) {
            my $rec_row = $recorded_rows->[$i];
            my $rep_row = $replayed_rows->[$i];
            if ($rec_row->[0] ne $rep_row->[0]) {
                push @mismatches, "assertion_id[$i] ($rep_row->[0] != $rec_row->[0])";
                last;
            }
            if ($rec_row->[1] ne $rep_row->[1]) {
                push @mismatches, "expected[$rec_row->[0]] ($rep_row->[1] != $rec_row->[1])";
                last;
            }
            if ($rec_row->[2] ne $rep_row->[2]) {
                push @mismatches, "actual[$rec_row->[0]] ($rep_row->[2] != $rec_row->[2])";
                last;
            }
        }
    }

    my $matches = @mismatches ? 0 : 1;
    my $op_verdict = $matches ? 'Passed' : 'Failed';
    my $op_status = $matches ? 0 : 1;

    atomic_write(
        "$out_abs/replay-result.json",
        $json->encode({
            operation_verdict => $op_verdict,
            operation_status  => $op_status,
            matches_recorded  => $matches ? JSON::PP::true : JSON::PP::false,
            native_returncode => $outcome->{native_returncode},
            replayed_verdict  => $replayed_res->{verdict},
            replayed_passed   => $replayed_res->{passed},
            replayed_failed   => $replayed_res->{failed},
            assertion_count   => scalar(@{$replayed_rows}),
            mismatches        => \@mismatches,
        }),
        0644,
    );

    my $summary = "Operation verdict: $op_verdict\n"
        . "Matches recorded: " . ($matches ? 'yes' : 'no') . "\n"
        . "Native returncode: $outcome->{native_returncode}\n"
        . "Replayed verdict: $replayed_res->{verdict}\n";
    for my $m (@mismatches) {
        $summary .= "Mismatch: $m\n";
    }
    atomic_write("$out_abs/replay-result.txt", $summary, 0644);
    print $summary;
    return $op_status;
}

sub main {
    my (@argv) = @_;
    if (!@argv) {
        die "missing subcommand (expected freeze, verify, replay, or --help)\n";
    }
    if ($argv[0] eq '--help' || $argv[0] eq '-h') {
        pod2usage(-exitval => 0, -verbose => 1, -output => \*STDOUT);
        return 0;
    }
    my $subcmd = shift @argv;
    return cmd_freeze(\@argv) if $subcmd eq 'freeze';
    return cmd_verify(\@argv) if $subcmd eq 'verify';
    return cmd_replay(\@argv) if $subcmd eq 'replay';
    die "unknown subcommand: $subcmd\n";
}

my $status;
eval {
    $status = main(@ARGV);
    defined $status or die "internal error: main returned no exit status\n";
    1;
} or do {
    my $error = $@;
    print STDERR "m2-replay.pl: $error";
    $status = 2;
};
exit $status;

__END__

=head1 NAME

m2-replay.pl - Freeze, verify, and replay M2 retained evaluation bundles

=head1 SYNOPSIS

  m2-replay.pl freeze --suite <suite> --run-dir <dir>
      --source-root <dir> --bundle-dir <new-dir> --pin-dir <new-dir>

  m2-replay.pl verify --bundle-dir <dir> --pin-dir <dir> [--output-dir <new-dir>]

  m2-replay.pl replay --bundle-dir <dir> --pin-dir <dir> --output-dir <new-dir>

  m2-replay.pl --help

=head1 DESCRIPTION

Packages a completed or incomplete M2 driver evidence directory together with
its shipped evaluator and fixture inputs, records an independent member and
dependency pin outside the bundle, verifies candidate bundles before launch,
and replays the shipped evaluator on fresh copies without modifying originals.

=head1 OPTIONS

=over 4

=item B<--suite> I<dual-startup|live-runtime|inventory-env|defaults-paths-hooks|services|protocols-autosave|faults>

Selects the evaluation contract during C<freeze>.

=item B<--run-dir> I<dir>

Selects the retained driver evidence directory during C<freeze>.

=item B<--source-root> I<dir>

Selects the repository or candidate source tree supplying the shipped evaluator
and fixtures during C<freeze>.

=item B<--bundle-dir> I<dir>

Names the new bundle directory for C<freeze>, or the candidate bundle directory
for C<verify> and C<replay>.

=item B<--pin-dir> I<dir>

Names the independent pin directory outside the candidate bundle.

=item B<--output-dir> I<dir>

Names a fresh output directory for C<replay> (and optionally C<verify>).

=item B<--help>, B<-h>

Prints usage documentation and exits 0.

=back

=head1 EXIT STATUS

=over 4

=item B<0>

Freeze or verification succeeded, or replay executed on verified copies and
reproduced the recorded evaluation semantically with unchanged inputs.

=item B<1>

Replay executed on verified copies and its native status, verdict, counts, or
assertion triples differed from the recorded receipt.

=item B<2>

Usage error, invalid bundle/pin/dependency state, corrupted member, or unusable
output destination. No evaluator process is started when pre-launch verification
returns 2.

=back

=cut
