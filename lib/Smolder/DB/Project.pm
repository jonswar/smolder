package Smolder::DB::Project;
use strict;
use warnings;
use base 'Smolder::DB';
use Smolder::DB::Developer;
use Smolder::Conf qw(InstallRoot);
use File::Path;
use File::Spec::Functions qw(catdir);
use DateTime::Format::MySQL;

__PACKAGE__->set_up_table('project');
__PACKAGE__->has_many('project_developers' => 'Smolder::DB::ProjectDeveloper');
__PACKAGE__->has_many('smoke_reports' => 'Smolder::DB::SmokeReport');

=head1 NAME

Smolder::DB::Project

=head1 DESCRIPTION

L<Class::DBI> based model class for the 'project' table in the database.

=head1 METHODS

=head2 ACCESSSOR/MUTATORS

Each column in the borough table has a method with the same name
that can be used as an accessor and mutator.

The following columns will return objects instead of the value contained in the table:

=cut

__PACKAGE__->has_a(
    start_date   => 'DateTime',
    inflate      => sub { DateTime::Format::MySQL->parse_datetime(shift) },
    deflate      => sub { DateTime::Format::MySQL->format_datetime(shift) },
);

# make sure we delete any test_report directories associated with us
__PACKAGE__->add_trigger(
    before_delete => sub {
        my $self = shift;
        my $dir = catdir(InstallRoot, 'data', 'smoke_reports', $self->id);
        rmtree($dir) if( -d $dir );
    }
);

=over

=item start_time

This is a L<DateTime> object representing the datetime stored.

=back

=cut

=head2 OBJECT METHODS

=head3 developers

Returns an array of all L<Smolder::DB::Developer> objects associated with this
Project (using the C<project_developer> join table.

=cut

sub developers {
    my $self = shift;
    my $sth = $self->db_Main->prepare_cached(qq(
        SELECT developer.* FROM developer, project_developer
        WHERE project_developer.project = ? AND project_developer.developer = developer.id
        ORDER BY project_developer.added
    ));
    $sth->execute($self->id);
    return Smolder::DB::Developer->sth_to_objects($sth);
}

=head3 has_developer

Return true if the given L<Smolder::DB::Developer> object is considered a member
of this Project.

    if( ! $project->has_developer($dev) ) {
        return "Unauthorized!";
    }

=cut

sub has_developer {
    my ($self, $developer) = @_;
    my $sth = $self->db_Main->prepare_cached(qq(
        SELECT COUNT(*) FROM project_developer
        WHERE project = ? AND developer = ?
    ));
    $sth->execute($self->id, $developer->id);
    return $sth->select_val || 0;
}

=head3 admins 

Returns a list of L<Smolder::DB::Developer> objects who are considered 'admins'
for this Project

=cut

sub admins {
    my $self = shift;
    my $sth = $self->db_Main->prepare_cached(qq(
        SELECT d.* FROM project_developer pd, developer d
        WHERE pd.project = ? AND pd.developer = d.id AND pd.admin = 1
        ORDER BY d.id
    ));
    $sth->execute($self->id);
    my @admins = Smolder::DB::Developer->sth_to_objects($sth);
    return @admins;
}

=head3 is_admin

Returns true if the given L<Smolder::DB::Developer> is considered an 'admin'
for this Project.

    if( $project->is_admin($developer) {
    ...
    }

=cut

sub is_admin {
    my ($self, $developer) = @_;
    if( $developer ) {
        my $sth = $self->db_Main->prepare_cached(qq(
            SELECT admin FROM project_developer
            WHERE developer = ? AND project = ?
        ));
        $sth->execute($developer->id, $self->id);
        my $row = $sth->fetchrow_arrayref();
        $sth->finish();
        return $row->[0];
    } else {
        return;
    }
}

=head3 clear_admins

Removes the 'admin' flag from any Developers associated with this Project.

=cut

sub clear_admins {
    my $self = shift;
    my $sth = $self->db_Main->prepare_cached(qq(
        UPDATE project_developer SET admin = 0
        WHERE project_developer.project = ?
    ));
    $sth->execute($self->id);
}

=head3 set_admins

Given a list of Developer id's, this method will set each Developer
to be an admin of the Project.

=cut

sub set_admins {
    my ($self, @admins) = @_;
    my $place_holders = join(', ', ('?') x scalar @admins); 
    my $sql = qq(
        UPDATE project_developer SET admin = 1
        WHERE project = ? AND developer IN ($place_holders)
    );
    my $sth = $self->db_Main->prepare_cached($sql);
    $sth->execute($self->id, @admins);
}

=head3 all_reports

Returns a list of L<Smolder::DB::SmokeReport> objects that are associate with this
Project in descending order (by default). You can provide optional 'limit' and 'offset' parameters
which will control which reports (and how many) are returned.

You can additionally specify a 'direction' parameter to specify the order in which they
are returned.

    # all of them
    my @reports = $project->all_reports();

    # just 5 most recent
    @reports = $project->all_reports(
        limit => 5
    );

    # the next 5
    @reports = $project->all_reports(
        limit   => 5,
        offset  => 5,
    );

    # in ascendig order
    @reports = $project->all_reports(
        direction   => 'ASC',
    );



=cut

sub all_reports {
    my ($self, %args) = @_;
    my $limit     = $args{limit} || 0;
    my $offset    = $args{offset} || 0;
    my $direction = $args{direction} || 'DESC';
    my $category  = $args{category};
    my @bind_vars = ($self->id);

    my $sql = q(
        SELECT smoke_report.* FROM smoke_report, project
        WHERE smoke_report.project = project.id 
        AND project.id = ?
    );
    if( $category ) {
        push(@bind_vars, $category);
        $sql .= " AND smoke_report.category = ? ";
    }

    $sql .= " ORDER BY added $direction, smoke_report.id DESC";
    $sql .= " LIMIT $offset, $limit " if( $limit );

    my $sth = $self->db_Main->prepare_cached($sql);
    $sth->execute(@bind_vars);
    return Smolder::DB::SmokeReport->sth_to_objects($sth);
}

=head3 report_count

The number of reports associated with this Project

=cut

sub report_count {
    my $self = shift;
    my $sql = q(
        SELECT COUNT(*) FROM smoke_report, project
        WHERE smoke_report.project = project.id
        AND project.id = ?
    );
    my $sth = $self->db_Main->prepare_cached($sql);
    $sth->execute($self->id);
    return $sth->select_val() || 0;
}

=head3 report_graph_data

Will return an array of arrays (based on the given fields) that
is suitable for feeding to GD::Graph. To limit the date range
used to build the data, you can also pass a 'start' and 'stop'
L<DateTime> parameter.

    my $data = $project->report_graph_data(
        fields  => [qw(total pass fail)],
        start   => $start,
        stop    => DateTime->today(),
    );

=cut

sub report_graph_data {
    my ($self, %args) = @_;
    my $fields = $args{fields};
    my $start = $args{start};
    my $stop = $args{stop};
    my $category = $args{category};
    my @data;
    my @bind_cols = ($self->id);

    # we need the date before anything else
    my $added = "DATE_FORMAT(added, '%m/%d/%Y')";
    
    my $sql = "SELECT " . join(', ', $added, @$fields) . " FROM smoke_report "
    . " WHERE project = ? AND invalid = 0 ";

    # if we need to limit by date
    if( $start ) {
        $sql .= " AND DATE(smoke_report.added) >= ? ";
        push(@bind_cols,$start->strftime('%Y-%m-%d'));
    }
    if( $stop ) {
        $sql .= " AND DATE(smoke_report.added) <= ? ";
        push(@bind_cols, $stop->strftime('%Y-%m-%d'));
    }

    if( $category ) {
        $sql .= " AND category = ? ";
        push(@bind_cols, $category);
    }

    my $sth = $self->db_Main->prepare_cached($sql);
    $sth->execute(@bind_cols);
    while( my $row = $sth->fetchrow_arrayref() ) {
        for my $i (0.. scalar(@$row) -1) {
            push(@{$data[$i]}, $row->[$i]);
        }
    }
    return \@data;
}

=head3 categories

Returns a list of all of categories that have been added to this project
(in the project_category table).

    my @categories = $project->categories();

=cut

sub categories {
    my $self = shift;
    my $sth = $self->db_Main->prepare_cached(qq(
        SELECT category FROM project_category WHERE project = ?
        ORDER BY category
    ));
    $sth->execute($self->id);
    my @cats;
    while( my $row = $sth->fetchrow_arrayref() ) {
        push(@cats, $row->[0]);
    }
    return @cats;
}

=head3 add_category

Adds the given category to this project.

    $project->add_category("Something New");

=cut

sub add_category {
    my ($self, $cat) = @_;
    my $sth = $self->db_Main->prepare_cached(qq(
        INSERT INTO project_category (project, category) VALUES (?,?)
    ));
    $sth->execute($self->id, $cat);
}

=head3 delete_category

Deletes a category in the project_category table associated with this Project.

    $project->delete_category("Something Old");

=cut

sub delete_category {
    my ($self, $cat) = @_;
    my $sth = $self->db_Main->prepare_cached(qq(
        DELETE FROM project_category WHERE project = ? AND category = ?
    ));
    $sth->execute($self->id, $cat);
}


=head2 CLASS METHODS

=head3 all_names

Returns an array containing all the names of all existing projects.
Can receive an extra arg that is the id of a project who's name should
not be returned.

=cut

sub all_names {
    my ($class, $id) = @_;
    my $sql = "SELECT NAME FROM project";
    $sql .= " WHERE id != $id" if( $id );
    my $sth = $class->db_Main->prepare_cached($sql);
    $sth->execute();
    my @names;
    while( my $row = $sth->fetchrow_arrayref() ) {
        push(@names, $row->[0]);
    }
    return @names;
}

1;
