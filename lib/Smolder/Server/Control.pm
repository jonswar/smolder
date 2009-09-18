package Smolder::Server::Control;
use File::Basename;
use File::Slurp;
use Getopt::Long qw(:config pass_through);
use Hash::MoreUtils qw(slice_def);
use Moose;
use Smolder::Conf;
use strict;
use warnings;

extends 'Server::Control::HTTPServerSimple';

__PACKAGE__->meta->make_immutable();

sub new_with_options {
    my ($class, %passed_params) = @_;

    # Get params from config file
    my $conf_file;
    GetOptions('f=s' => \$conf_file);
    die "must specify -f|--conf-file" unless defined($conf_file);
    my $conf_dir = dirname($conf_file);
    Smolder::Conf->init_from_file($conf_file);
    require Smolder::Server;

    my $server = Smolder::Server->new();

    my %net_server_params = (
        pid_file => Smolder::Conf->get('PidFile'),
        log_file => Smolder::Conf->get('LogFile'),
        port     => Smolder::Conf->get('Port'),
        user     => Smolder::Conf->get('User'),
        group    => Smolder::Conf->get('Group'),
    );
    %net_server_params = slice_def(\%net_server_params, keys(%net_server_params));

    return $class->SUPER::new_with_options(
        server_class      => 'Smolder::Server',
        net_server_params => \%net_server_params,
        name              => sprintf("smolder (%s)", $conf_dir),
    );
}

1;
