package File::Find::Rule::Git::ChangedRecently;

use parent 'File::Find::Rule';
use strict;
use warnings;

use Git::Helpers;

=head1 NAME

File::Find::Rule::Git::ChangedRecently - Find files changed recently in git

=head1 VERSION

This is version 0.001.

=cut

our $VERSION = '0.001';
$VERSION = eval $VERSION;

=head1 SYNOPSIS

 use File::Find::Rule::Git::ChangedRecently;

 my @changed_files = File::Find::Rule->file
     ->changed_in_git_since_branch('origin/master')
     ->in('/path/to/git/checkout');

=head1 DESCRIPTION

This is an extension to File::Find::Rule that knows about git. It provides an
additional matching rule that lets you say "only files changed since we 
branched from master" (or whatever other branch); you can then pass that
smaller list of files to perlcritic, Devel::Cover, etc. etc.

=head1 Methods

=head2 Matching Rules

=over

=item changed_in_git_since_branch ($branch_name)

Limits the files found to only those that have changed in git since the current
branch was branched from C<$branch_name>.

NB: if the head is currently detached (e.g. because you're running under a
build), a simple branch name like C<master> will fail as, from git's point of
view, there I<are> no branches. Say C<origin/master> instead.

If the directory you pass to File::Find::Rule->in or File::Find::Rule->start
isn't under a git checkout, those methods will throw an exception that looks
like C<Not a git repository (or any of the parent directories)>.

=cut

sub File::Find::Rule::changed_in_git_since_branch {
    my ($invocant, $branch_name) = @_;
    my $self = $invocant->_force_object;

    $self->exec(
        sub {
            # First of all, make sure we have a git checkout. We won't use the
            # return value of this, we just want to make sure that it didn't
            # throw an exception.
            Git::Helpers::checkout_root($File::Find::name);
        }
    );
}

=back

=cut

=head1 SEE ALSO

L<File::Find::Rule>.

=head1 AUTHOR

Sam Kington <skington@cpan.org>

The source code for this module is hosted on GitHub
L<https://github.com/skington/file-find-rule-git-changedrecently> - this is
probably the best place to look for suggestions and feedback.

=head1 COPYRIGHT

Copyright (c) 2020 Sam Kington.

=head1 LICENSE

This library is free software and may be distributed under the same terms as
perl itself.

=cut

1;
