package Smolder::Server;
use strict;
use warnings;
use base 'CGI::Application::Server';
use File::Path qw(mkpath);
use Smolder::Conf qw(DataDir Port HostName HtdocsDir);
use Smolder::DB;

sub new {
    my $class = shift;
    my $server = $class->SUPER::new(@_);
    $server->host(HostName);
    # $server->port(Port);
    # $server->pid_file(PidFile);

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
    return $server;
}

sub net_server { 'Smolder::Server::PreFork' }

sub run {
    my $self = shift;

    # Create data dir if needed
    if (not -e DataDir) {
        mkpath(DataDir) or die sprintf("Could not create %s: $!", DataDir);
    }

    unless (-e Smolder::DB->db_file) {

        # do we have a database? If not then create one
        Smolder::DB->create_database;
    } else {

        # upgrade if we need to
        require Smolder::Upgrade;
        Smolder::Upgrade->new->upgrade();
    }

    # preload our perl modules
    require Smolder::Dispatch;
    require Smolder::Control;
    require Smolder::Control::Admin;
    require Smolder::Control::Admin::Developers;
    require Smolder::Control::Admin::Projects;
    require Smolder::Control::Developer;
    require Smolder::Control::Developer::Graphs;
    require Smolder::Control::Developer::Prefs;
    require Smolder::Control::Developer::Projects;
    require Smolder::Control::Public;
    require Smolder::Control::Public::Auth;
    require Smolder::Control::Public::Graphs;
    require Smolder::Control::Public::Projects;
    require Smolder::Redirect;

    $self->SUPER::run(@_);
}

1;
