#!/usr/bin/perl -w
# Display services which need to be restarted, because they are still
# using old copies of libraries.
# Written by Richard W.M. Jones <rjones@redhat.com>
# License: GNU General Public License version 2 or above
# Requires:
#   - lsof
#   - systemctl

use strict;

# Parse lsof output.
my @lines = qx{ lsof };
my @procs = ();
foreach (@lines) {
    chomp;
    my @fields = split;
    if ($fields[4] eq "DEL" && $fields[8] =~ /\.so/) {
        my $comm = $fields[0];
        my $pid = $fields[1];
        my $user = $fields[3];
        my $file = $fields[8];
        $file =~ s/;[a-f0-9]{8}//;
        push @procs,
        { comm => $comm, pid => $pid, user => $user, file => $file };
    }
}

# Resolve PID to systemctl service, and file to package.
my $proc;
my %services_cache;
my %pkgs_cache;
my %pkgs_service_restart;
my %pkgs_scope_restart;
my %pkgs_pid_restart;
foreach $proc (@procs) {
    unless (exists $services_cache{$proc->{pid}}) {
        my $service = `systemctl status $proc->{pid} | head -1`;
        chomp $service;
        $services_cache{$proc->{pid}} = $service;
    }
    my $service = $services_cache{$proc->{pid}};

    unless (exists $pkgs_cache{$proc->{file}}) {
        my $pkg = `rpm -qf $proc->{file} 2>&-`;
        chomp $pkg;
        $pkgs_cache{$proc->{file}} = $pkg ? $pkg : "";
    }
    my $pkg = $pkgs_cache{$proc->{file}};

    if ($service =~ /\.service - /) {
        if (exists $pkgs_service_restart{$pkg}) {
            my $h = $pkgs_service_restart{$pkg};
            $h->{$service} = 1;
        } else {
            $pkgs_service_restart{$pkg} = { $service => 1 }
        }
    } elsif ($service =~ /\.scope - /) {
        if (exists $pkgs_scope_restart{$pkg}) {
            my $h = $pkgs_scope_restart{$pkg};
            $h->{$service} = 1;
        } else {
            $pkgs_scope_restart{$pkg} = { $service => 1 }
        }
    } else {
        if (exists $pkgs_pid_restart{$pkg}) {
            push @{$pkgs_pid_restart{$pkg}}, $proc;
        } else {
            $pkgs_pid_restart{$pkg} = [ $proc ]
        }
    }
}

# Print out the services to restart summary.
foreach my $pkg (keys %pkgs_service_restart) {
    print "In order to complete the installation of $pkg,\n";
    print "you should restart the following services:\n";
    print "\n";
    my %services = %{$pkgs_service_restart{$pkg}};
    foreach (keys %services) {
        print "    - $_\n"
    }
    print "\n";
}

# Print out the scopes to restart summary.
foreach my $pkg (keys %pkgs_scope_restart) {
    print "In order to complete the installation of $pkg,\n";
    print "you should tell the following users to log out and log in:\n";
    print "\n";
    my %services = %{$pkgs_scope_restart{$pkg}};
    foreach (keys %services) {
        print "    - $_\n"
    }
    print "\n";
}

# Print out the PIDs to restart summary.
foreach my $pkg (keys %pkgs_pid_restart) {
    print "In order to complete the installation of $pkg,\n";
    print "you should restart the following processes:\n";
    print "\n";
    my @ps = @{$pkgs_pid_restart{$pkg}};
    foreach (@ps) {
        print "    - $_->{comm}, PID $_->{pid} owned by $_->{user}\n"
    }
    print "\n";
}
