package Smolder::Server::Control;
use File::Basename;
use File::Slurp;
use Moose;
use Smolder::Conf;
use strict;
use warnings;

extends 'Server::Control::Simple';

__PACKAGE__->meta->make_immutable();

sub BUILDARGS {
    my $class = shift;
    my %params = @_;
    my $config_file = delete($params{config_file}) or die "must specify config_file";
    my $config_dir = dirname($config_file);
    
    Smolder::Conf->init_from_file($config_file);
    require Smolder::Server;

    my $server = Smolder::Server->new();

    return $class->SUPER::BUILDARGS(
        description => "smolder ($config_dir)",
        server      => $server,
        pid_file    => Smolder::Conf->get('PidFile'),
        error_log   => Smolder::Conf->get('LogFile'),
        port        => Smolder::Conf->get('Port'),
        %params
    );
}

1;
