package Smolder::Server::Control;
use File::Basename;
use Moose;
use Smolder::Conf;
use strict;
use warnings;

extends 'Server::Control::HTTPServerSimple';

__PACKAGE__->meta->make_immutable();

sub new_from_config {
    my ($class, $config_file) = @_;
    die "must specify config_file" unless defined($config_file);
    my $config_dir = dirname($config_file);
    
    Smolder::Conf->init_from_file($config_file);
    require Smolder::Server;

    my $server = Smolder::Server->new();

    return $class->new(
        server_class => 'Smolder::Server',
        net_server_params => {
            pid_file   => Smolder::Conf->get('PidFile'),
            log_file   => Smolder::Conf->get('LogFile'),
            port       => Smolder::Conf->get('Port'),
            user       => Smolder::Conf->get('User'),
            group      => Smolder::Conf->get('Group'),
        },
        description => "smolder ($config_dir)"
    );
}

1;
