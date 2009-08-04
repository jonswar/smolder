package Smolder::Server;
use strict;
use warnings;
use base 'CGI::Application::Server';
use File::Spec::Functions qw(catdir devnull catfile);
use File::Path qw(mkpath);
use Smolder::Conf qw(Port HostName HtdocsDir);
use Smolder::DB;

sub new {
    my ($class, %args) = @_;
    my $server = $class->SUPER::new(@_);
    $server->host(HostName);
    $server->port(Port);
    $server->pid_file(PidFile);

    $server->entry_points(
        {
            '/'           => 'Smolder::Redirect',
            '/app'        => 'Smolder::Dispatch',
            '/js'         => HtdocsDir,
            '/style'      => HtdocsDir,
            '/images'     => HtdocsDir,
            '/robots.txt' => HtdocsDir,
        },
    );
    $server->{"__smolder_$_"} = $args{$_} foreach keys %args;
    return $server;
}

sub net_server { 'Smolder::Server::PreFork' }

1;
