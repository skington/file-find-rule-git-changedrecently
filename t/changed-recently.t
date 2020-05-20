#!/usr/bin/env perl
# Test that we can get an accurate list of files that have changed
# since a branch was last branched from its parent branch (or, possibly,
# any other branch).

use strict;
use warnings;

use Capture::Tiny qw(capture);
use Cwd;
use File::pushd qw(pushd);
use File::Spec;
use File::Temp;
use Test::Fatal;
use Test::More;

use_ok('File::Find::Rule::Git::ChangedRecently');

my %mac_os_versions = _mac_os_version_details();

subtest('We must be able to find a .git directory'  => \&test_find_git);
if ($ENV{AUTHOR_TESTING}) {
    subtest('We can cope with the root directory being gitted' =>
            \&sabotage_root_directory);
}
our $repository_root;
subtest('Comparing master with master is pointless' => \&test_compare_master);

done_testing();

# Obviously if there's no .git directory to be found we can't do anything
# git-related.

sub test_find_git {
    my $rootdir = File::Spec->rootdir;

    # There better not be a git checkout in the root directory already,
    # because if there is we can't recover from any random directory *not*
    # being under git, because the whole goddamn filesystem will be in
    # this case.
    if (-d File::Spec->catfile($rootdir, '.git')) {
        my $cwd = Cwd::cwd();
        chdir($rootdir);
        like(
            `git status`,
            qr/Untracked files/,
            "For some unfathomable reason the root directory $rootdir"
                . ' is already a git checkout? Smile and nod'
        );
        chdir($cwd);
        return;
    }

    my $rule = File::Find::Rule->changed_in_git_since_branch('master');
    like(
        exception { $rule->in($rootdir); },
        qr/git repository/,
        q{The root directory isn't a git checkout, so :shrug-emoji:}
    );
}

# If we know that we're the author (and can therefore assume that we have
# sudo and can write to the root directory), create a git repository there
# to get 100% code coverage.
# It's OK for this stuff to be Unix-specific because this is an author test,
# and you won't get me running Windows any time soon. Or, if you do, I'll
# fix it.

sub sabotage_root_directory {
    my $cwd = Cwd::cwd();
    my $rootdir = File::Spec->rootdir;
    chdir($rootdir);
    ok(system('sudo', 'git', 'init') == 0,
        'Gitify the root directory like an absolute maniac');
    test_find_git();
    ok(
        system('sudo', 'rm', '-fr', $rootdir . '/.git') == 0,
        'We can get rid of this idiocy'
    );
    chdir($cwd);
}

# Even with a basic git repository and a series of commits, comparing master
# with master will by necessity produce nothing.

sub test_compare_master {
    # Make sure we have a repository directory. Change to it, so git knows
    # where we mean to create our repository.
    $repository_root
        ||= File::Temp->newdir(
        'file-find-rule-git-changedrecently-repository-XXXX',
        TMPDIR => 1);
    my $dir = pushd($repository_root);

    # Set up a git repository.
    git_ok('We can set up a git repository in our new directory', 'init');
    my $rule = File::Find::Rule->changed_in_git_since_branch('master');
    my @files_changed;
    my $exception;
    my $find_files = sub {
        $exception = exception { @files_changed = $rule->in($repository_root) };
    };
    $find_files->();
    ok(
        !$exception,
        'No exception thrown by looking for changed files'
    ) or diag($exception);
    is(@files_changed, 0, q{But we didn't find anything});

    # Add a few files. They're ignored because they haven't changed
    # since master (because we're *in* master).
    open(my $fh, '>', 'README');
    print $fh "All things Mac OS!\n";
    close $fh;
    git_ok('Add the README', 'add', 'README');
    git_ok(
        'Commit this README',
        'commit', '--message', 'We have a README now'
    );
    open($fh, '>', '.gitignore');
    print $fh ".*\n";
    close $fh;
    git_ok('Add the .gitignore', 'add', '--force', '.gitignore');
    git_ok(
        'Commit a .gitignore as well',
        'commit', '--message', 'Ignore dotfiles'
    );
    open($fh, '>', 'mac-os-versions');
    for my $os_details (@{ $mac_os_versions{cats} }) {
        printf $fh "%s: %s (%s)\n",
            @$os_details{qw(codename release_date os_url)};
    }
    close $fh;
    git_ok('Add mac-os-versions', 'add', 'mac-os-versions');
    git_ok(
        'Commit the first iteration of Mac OS versions',
        'commit', '--message', 'Big cat Mac OS versions'
    );
    $find_files->();
    ok(!$exception, 'Still no exception, now that we have a commit history')
        or diag($exception);
    is(@files_changed, 0, q{But we still didn't find anything});
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

sub _mac_os_version_details {
    return (
        cats => [
            {
                codename     => 'Cheetah',
                release_date => '2001-03-24',
                os_url       => 'https://en.wikipedia.org/wiki/Mac_OS_X_10.0',
            },
            {
                codename     => 'Puma',
                release_date => '2001-09-25',
                os_url       => 'https://en.wikipedia.org/wiki/Mac_OS_X_10.1',
            },
            {
                codename     => 'Jaguar',
                release_date => '2002-08-23',
                os_url       => 'https://en.wikipedia.org/wiki/Mac_OS_X_10.2',
            },
            {
                codename     => 'Panther',
                release_date => '2003-10-24',
                os_url => 'https://en.wikipedia.org/wiki/Mac_OS_X_Panther',
            },
            {
                codename     => 'Tiger',
                release_date => '2005-04-29',
                os_url => 'https://en.wikipedia.org/wiki/Mac_OS_X_Tiger',
            },
            {
                codename     => 'Leopard',
                release_date => '2007-10-26',
                os_url => 'https://en.wikipedia.org/wiki/Mac_OS_X_Leopard',
            },
            {
                codename     => 'Snow Leopard',
                release_date => '2009-08-28',
                os_url =>
                    'https://en.wikipedia.org/wiki/Mac_OS_X_Snow_Leopard',
            },
            {
                codename     => 'Lion',
                release_date => '2011-07-20',
                os_url       => 'https://en.wikipedia.org/wiki/Mac_OS_X_Lion',
            },
            {
                codename     => 'Mountain Lion',
                release_date => '2012-07-25',
                os_url => 'https://en.wikipedia.org/wiki/OS_X_Mountain_Lion',
            }
        ],
        california => [
            {
                codename     => 'Mavericks',
                release_date => '2013-10-22',
                os_url => 'https://en.wikipedia.org/wiki/OS_X_Mavericks',
            },
            {
                codename     => 'Yosemite',
                release_date => '2014-10-16',
                os_url       => 'https://en.wikipedia.org/wiki/OS_X_Yosemite',
            },
            {
                codename     => 'El Capitan',
                release_date => '2015-09-30',
                os_url => 'https://en.wikipedia.org/wiki/OS_X_El_Capitan',
            },
            {
                codename     => 'Sierra',
                release_date => '2016-09-20',
                os_url       => 'https://en.wikipedia.org/wiki/MacOS_Sierra',
            },
            {
                codename     => 'High Sierra',
                release_date => '2017-09-25',
                os_url => 'https://en.wikipedia.org/wiki/MacOS_High_Sierra',
            },
            {
                codename     => 'Mojave',
                release_date => '2018-09-24',
                os_url       => 'https://en.wikipedia.org/wiki/MacOS_Mojave',
            },
            {
                codename     => 'Catalina',
                release_date => '2019-10-07',
                os_url => 'https://en.wikipedia.org/wiki/MacOS_Catalina',
            }
        ],
    );
}

sub git_ok {
    my ($title, @git_args) = @_;

    my ($stdout, $stderr, $exit_code) = capture { system('git', @git_args); };
    ok($exit_code == 0, $title)
        or diag sprintf(
        "When running git %s:\nSTDOUT:\n%s\n\nSTDERR:\n%s\n\n",
        join(' ', @git_args),
        $stdout, $stderr
        );
}

