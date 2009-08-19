package Smolder::Server::PreFork;
use Smolder::Conf qw(LogFile);
use strict;
use warnings;
use base qw(Net::Server::PreFork);

sub post_configure_hook {
    my $self = shift;
    my $prop = $self->{server};

    # This all runs in the child, after forking
    #

    # Send warnings to our logs
    my $log_file = LogFile || devnull();
    my $ok = open(STDERR, '>>', $log_file);
    if (!$ok) {
        warn "Could not open logfile $log_file for appending: $!";
        exit(1);
    }
}

1;
