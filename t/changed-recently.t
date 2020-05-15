#!/usr/bin/env perl
# Test that we can get an accurate list of files that have changed
# since a branch was last branched from its parent branch (or, possibly,
# any other branch).

use strict;
use warnings;

use File::Spec;
use Test::Fatal;
use Test::More;

use_ok('File::Find::Rule::Git::ChangedRecently');

subtest('We must be able to find a .git directory' => \&test_find_git);

done_testing();

# Obviously if there's no .git directory to be found we can't do anything
# git-related.

sub test_find_git {
    my $rootdir = File::Spec->rootdir;
    my $rule = File::Find::Rule->changed_in_git_since_branch('master');
    like(
        exception { $rule->in($rootdir) },
        qr/git repository/,
        q{The root directory isn't a git checkout, so :shrug-emoji:}
    );
}

=for reference

Create a new git repository. Add a README and a .gitignore, as separate commits.
We now don't crash, but we return nothing, because there aren't branches.
Test that we even don't crash if we're not in that directory.

If we ask to compare with a branch that doesn't exist, though, we get errors.

Test that:
* we cope with files being renamed
* we can cope with symlinks
* we're not just dealing with date-based comparisons: make changes in master
  and our branch doesn't pick those changes up.
* we're dealing with individual branches: branch of another branch,
  and the second branch has a much more limited set of changes compared to
  its immediate branch than when compared to master.
* merge the first branch: the second branch still has shitloads of changes
  compared to master because its base is the *old* maser.
* but the first branch has no changes compared to master
* merge master into the second branch: we now have a smaller set of changes.

Start out with just a list of Mac OS versions, all in one file, with
release dates and wikipedia URL for the version of mac OS.
New branch "references" gets rid of the one file and creates directories for
all the cat-named versions, with release-date and url files.
In master we add the California details; this causes a merge conflict.
We undelete the file in the branch and merge.

In a separate branch we add cat links, including symlinks when we already
know about Puma vs Mountain Lion.


=cut

