package File::Find::Rule::Git::ChangedRecently;

use parent 'File::Find::Rule';
use strict;
use warnings;

use Carp;
use Capture::Tiny qw(capture);
use Cwd;
use English qw(-no_match_vars);
use File::pushd qw(pushd);
use Path::Class::Dir;

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

    my %changed_in_checkout;
    $self->exec(
        sub {
            # Get the canonical path, and see if we've found a checkout
            # anywhere.
            my $current_dir = Path::Class::Dir->new($File::Find::dir);
            my ($parent_dir, $checkout_root);
            dir:
            while (1) {
                # If we've seen this directory before, no need to work
                # everything out a second time.        
                if ($changed_in_checkout{$current_dir->stringify}) {
                    $checkout_root = $current_dir->stringify;
                    last dir;
                }

                # Maybe we know about the parent directory?
                # (If it's the same as this one, that means "we're at the top
                # of the directory tree", so avoid an infinite loop and stop
                # now.)
                my $parent_dir = $current_dir->parent;
                if ($parent_dir->stringify eq $current_dir->stringify) {
                    last dir;
                }
                $current_dir = $parent_dir;
            }

            # OK, we have no idea about this repository. Find out.
            if (!$checkout_root) {
                # Git doesn't understand file names, so change temporarily
                # to the directory we found this file in.
                my $dir = pushd($File::Find::dir);

                # Find the top level directory for this repository.
                # This will throw an exception if we're not in a git
                # directory.
                $checkout_root = _git('rev-parse', '--show-toplevel');

                # We're in a git working directory, so find out where
                # this diverged from the branch we're interested in.
                ### TODO: is --fork-point better here?
                my $branch_points;
                eval {
                    $branch_points
                        = _git('merge-base', '--all', 'HEAD', $branch_name);
                    1;
                } or do {
                    # We'll get this if we're in a repository with no commits
                    # yet.
                    if ($EVAL_ERROR =~ /Not a valid object name HEAD/) {
                        $changed_in_checkout{$checkout_root} = [];
                        return 0;
                    }
                    carp "Couldn't do git merge-base: $EVAL_ERROR";
                };
                my $first_branch_point = (split(/\n/, $branch_points))[0];

                # Now find the files that are different.
                my $diff_list
                    = _git('diff', '--name-status', $first_branch_point);
                $changed_in_checkout{$checkout_root} = 'TODO: find stuff';
            }
            
            ### TODO: work out if something has in fact changed.
            return 0;
        }
    );
}

sub _git {
    my ($command, @arguments) = @_;

    my ($stdout, $stderr, $exit) = capture {
        system('git', $command, @arguments);
    };
    if ($exit != 0) {
        die $stderr;
    }
    return $stdout;
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
