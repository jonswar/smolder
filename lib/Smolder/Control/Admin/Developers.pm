package Smolder::Control::Admin::Developers;
use strict;
use warnings;
use base 'Smolder::Control';
use Smolder::DB::Project;
use Smolder::DB::Developer;
use Smolder::Email;
use Smolder::Constraints qw(email unsigned_int length_max length_between bool unique_field_value);
use Email::Valid;

sub setup {
    my $self = shift;
    $self->start_mode('list');
    $self->run_modes([qw(
        add
        process_add
        edit
        process_edit
        list
        details
        delete
        process_delete
        reset_pw
        process_reset_pw
    )]);
}

sub reset_pw {
    my ($self, $err_msgs) = @_;
    return $self->tt_process({
        developer => Smolder::DB::Developer->retrieve($self->param('id')),
    });
}

sub process_reset_pw {
    my $self = shift;
    my $developer = Smolder::DB::Developer->retrieve($self->param('id'));
    return $self->error_message("Developer no longer exists!")
        unless $developer;

    my $new_pw = $developer->reset_password();
    Smolder::DB->dbi_commit();

    # send the email
    my $error = Smolder::Email->send_mime_mail(
        name        => 'reset_pw',
        to          => $developer->email,
        subject     => 'Reset of password by Admin',
        tt_params   => {
            developer   => $developer,
            new_pw      => $new_pw,
        }, 
    );
    if( $error ) {
        my $msg = "Could not send 'reset_pw' email to " . $developer->email ."!";
        warn "[WARN] - $msg - $error";
        return $self->error_message($msg);
    } else {
        return $self->details($developer, 'reset_pw');
    }
}

sub edit {
    my ($self, $err_msgs) = @_;
    my $developer = Smolder::DB::Developer->retrieve($self->param('id'));
    my $output;
    # if we have any error messages, then just re-fill the form
    # and show them
    if( $err_msgs ) {
        $err_msgs->{developer} = $developer;
        $output = HTML::FillInForm->new->fill(
            scalarref   => $self->tt_process($err_msgs),
            qobject     => $self->query,
        );
    # else get the developer in question
    } else {
        my %developer_data = $developer->vars();
        $output = HTML::FillInForm->new->fill(
            scalarref   => $self->tt_process({ developer => $developer }),
            fdat        => \%developer_data,
        );
    }
    return $output;
}

sub process_edit {
    my $self = shift;
    my $id = $self->param('id');
    my $form = {
        required    => [qw(username fname lname email admin)],
        constraint_methods => {
            username    => [
                length_max(255),
                unique_field_value('developer', 'username', $id),
            ],
            fname       => length_max(255),
            lname       => length_max(255),
            email       => email(),
            admin       => bool(),
        },
    };

    my $results = $self->check_rm('edit', $form)
        || return $self->check_rm_error_page;
    my $valid = $results->valid();

    my $developer = Smolder::DB::Developer->retrieve( $id );
    return $self->error_message("Developer no longer exists!")
        unless $developer;
    $developer->set(%$valid);
    # we need to eval{} since we don't want there to be duplicate usernames (id)
    eval { $developer->update };
        
    # if there was a problem.
    if( $@ ) {
        # if it was a duplicate developer, then we can handle that
        if( $@ =~ /Duplicate entry/ ) {
            return $self->add({ err_unique_username => 1});
        # else it's something else, so just throw it again
        } else {
            die $@;
        }
    }
    Smolder::DB->dbi_commit();

    # now show the developer's details page
    return $self->details($developer, 'edit');
}

sub list {
    my $self = shift;
    my @developers = Smolder::DB::Developer->retrieve_all();
    my %tt_params;
    $tt_params{developers} = \@developers if( @developers );
    return $self->tt_process(\%tt_params);
}

sub add {
    my ($self, $tt_params) = @_;
    $tt_params ||= {};
    return $self->tt_process($tt_params);
}

sub process_add {
    my $self = shift;
    my $form = {
        required    => [qw(username fname lname email password admin)],
        constraint_methods => {
            username    => [
                length_max(255),
                unique_field_value('developer', 'username'),
            ],
            fname       => length_max(255),
            lname       => length_max(255),
            email       => email(),
            password    => length_between(4, 255),
            admin       => bool(),
        },
    };

    my $results = $self->check_rm('add', $form)
        || return $self->check_rm_error_page;
    my $valid = $results->valid();

    # create a new preference for this developer;
    my $pref = Smolder::DB::Preference->create({});
    $valid->{preference} = $pref;
    my $developer;
    # we need to eval{} since we don't want there to be duplicate usernames
    eval { $developer = Smolder::DB::Developer->create($valid) };

    # if there was a problem.
    if( $@ ) {
        # if it was a duplicate developer, then we can handle that
        if( $@ =~ /Duplicate entry/ ) {
            return $self->add({ err_unique_username => 1});
        # else it's something else, so just throw it again
        } else {
            die $@;
        }
    }
    Smolder::DB->dbi_commit();

    # now show the developer's details page
    return $self->details($developer, 'add');
}

sub details {
    my ($self, $developer, $action) = @_;
    my $new;
    # if we weren't given a developer, then get it from the query string
    if(! $developer ) {
        my $id = $self->param('id');
        $new = 0;
        $developer = Smolder::DB::Developer->retrieve($id);
        return $self->error_message("Can't find Developer with id '$id'!") unless $developer;
    } else {
        $new = 1;
    }

    my %tt_params = (
        developer => $developer
    );
    $tt_params{$action} = 1 if( $action );

    return $self->tt_process(\%tt_params);
}

sub process_delete {
    my $self = shift;
    my $id = $self->param('id');
    my $developer = Smolder::DB::Developer->retrieve($id);

    # remove all reports from this developer
    my @smokes = $developer->smoke_reports();
    foreach my $smoke (@smokes) {
        $smoke->delete_files();
    }

    $developer->delete();
    Smolder::DB->dbi_commit();

    return $self->list();
}


1;
