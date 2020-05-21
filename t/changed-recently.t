#!/usr/bin/env perl
# Test that we can get an accurate list of files that have changed
# since a branch was last branched from its parent branch (or, possibly,
# any other branch).

use strict;
use warnings;

use Capture::Tiny qw(capture);
use Cwd;
use Data::Dumper;
use English qw(-no_match_vars);
use File::pushd qw(pushd);
use File::Spec;
use File::Temp;
use Test::Requires::Git;
use Test2::V0;

use File::Find::Rule::Git::ChangedRecently;

test_requires_git();

my %mac_os_versions = _mac_os_version_details();

subtest('We must be able to find a .git directory'  => \&test_find_git);
if ($ENV{AUTHOR_TESTING}) {
    subtest('We can cope with the root directory being gitted' =>
            \&sabotage_root_directory);
}
our $repository_root;
subtest('Comparing master with master is pointless' => \&test_compare_master);
subtest('We find changes in a branch'  => \&test_find_simple_branch_changes);
subtest('Branches must exist'          => \&test_compare_non_existent_branch);
subtest('We cope with complex changes' => \&test_find_complex_branch_changes);

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
        dies { $rule->in($rootdir); },
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
# This sets up master with a few commits, and sets $repository_root.

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
    my @files_changed;
    my ($rule, $exception);
    my $find_files = sub {
        $rule = File::Find::Rule->changed_in_git_since_branch('master');
        $exception
            = dies { @files_changed = $rule->in($repository_root) };
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

# Once we add files to a branch, they're picked up.

sub test_find_simple_branch_changes {
    # Create a new branch and expand the list of Mac OS versions into
    # individual files.
    my $dir = pushd($repository_root);
    git_ok('Create a new branch',   'branch',   'structured');
    git_ok('Switch to that branch', 'checkout', 'structured');
    my @expect_files_changed;
    mkdir('mac os versions', 0755);
    my $mac_os_dir = pushd('mac os versions');
    for my $os_details (@{ $mac_os_versions{cats} }) {
        mkdir($os_details->{codename}, 0755);
        my $release_dir = pushd($os_details->{codename});
        for my $field (qw(release_date os_url)) {
            open(my $fh, '>', $field);
            print $fh $os_details->{$field};
            close $fh;
            git_ok(
                sprintf('Add %s %s %s',
                    $os_details->{codename}, $field,
                    $os_details->{$field}),
                'add', $field
            );
            push @expect_files_changed,
                File::Spec->catfile(
                $repository_root,
                'mac os versions',
                $os_details->{codename}, $field
                );
        }
    }
    undef $mac_os_dir;
    git_ok(
        'Commit this bunch of new files',
        'commit', '--message', 'Split these details into directories'
    );
    my @files_changed
        = File::Find::Rule->changed_in_git_since_branch('master')
        ->in($repository_root);
    is(
        [sort @files_changed],
        [sort @expect_files_changed],
        'We picked up all the added files'
    ) or diag dumper(@files_changed);
}

# You can't compare changes from a non-existent branch.

sub test_compare_non_existent_branch {
    my ($stdout, $stderr, @files_changed) = capture {
        File::Find::Rule->changed_in_git_since_branch('no_such_branch')
            ->in($repository_root);
    };
    is(scalar @files_changed, 0,
        'No files found compared to a non-existent branch');
    like(
        $stderr,
        qr{
            ^
            \QCouldn't find divergence point from branch no_such_branch\E
           .+
           \Qvalid object name\E
        }xi,
        'We complained about a bad branch name'
    );
}

# We can cope with files being deleted and moved about.

sub test_find_complex_branch_changes {
    my $dir = pushd($repository_root);
    my $find_files_master = sub {
        File::Find::Rule->changed_in_git_since_branch('master')
            ->in($repository_root)
    };

    # Add a changed mac-os-versions file in master. It doesn't show up in
    # the list of changed files, because while it's changed in master,
    # it hasn't changed in *this* branch, nor in the part of master that this
    # branch was branched from. It doesn't matter that it's been changed
    # recently, because we're not looking at the entire version control tree,
    # just this branch and its history.
    git_ok('Switch back to master', 'checkout', 'master');
    open(my $fh, '>>', 'mac-os-versions');
    for my $os_details (@{ $mac_os_versions{california} }) {
        printf $fh "%s: %s (%s)\n",
            @$os_details{qw(codename release_date os_url)};
    }
    close $fh;
    git_ok('Commit this extended list of Mac OS versions',
        'commit', '--all', '--message', 'Know about newer versions of Mac OS');
    git_ok('Switch back to the structured branch',
        'checkout', 'structured');
    my @files_changed = $find_files_master->();
    ok(
        !(grep { $_ eq 'mac-os-versions' } @files_changed),
        'No changes in mac-os-versions since this branch was created'
            . '; changes in master *since* then, but so what?'
    );

    # Back in the structured branch, move mac-os-versions to indicate that
    # it's not as important. We spot the rename.
    git_ok(
        'Move that old text file somewhere less prominent',
        'mv',
        'mac-os-versions',
        File::Spec->catfile('mac os versions', 'summary')
    );
    git_ok('Commit this change',
        'commit', '--message', 'Tidy this out of the way');
    @files_changed = $find_files_master->();
    ok(!(grep { /mac-os-versions/ } @files_changed),
        'No sign of the old file - because it no longer exists');
    ok((grep { /summary/ } @files_changed),
        'The summary file is marked as having been renamed');

    # Right, create a third branch, branched from the structured branch.
    # This is where we'll add details of the various Wikipedia articles about
    # the big cats that Mac OS versions are named after.
    git_ok('Create a third branch, for more links', 'branch',   'more_links');
    git_ok('Switch to it',                          'checkout', 'more_links');
    my $mac_os_dir = pushd('mac os versions');
    for my $os_details (@{ $mac_os_versions{cats} }) {
        my $release_dir = pushd($os_details->{codename});
        open (my $fh, '>', 'subject_url');
        print $fh $os_details->{subject_url};
        close $fh;
        git_ok('Add a subject URL for ' . $os_details->{codename},
            'add', 'subject_url');
    }
    git_ok(
        'Add these subject URL files',
        'commit', '--message', 'Say what these refer to'
    );

    # They show up if we compare this branch to master, obviously.
    # If we compare this branch with the structured branch, they're *all*
    # that shows up.
    my @all_files_changed = $find_files_master->();
    my @subject_url_files_changed = grep { /subject_url/ } @all_files_changed;
    is(
        scalar @subject_url_files_changed,
        scalar @{ $mac_os_versions{cats} },
        'We have a subject_url file for each cat-themed version of Mac OS'
    );
    my $find_files_structured_branch = sub {
        File::Find::Rule->changed_in_git_since_branch('structured')
            ->in($repository_root)
    };
    my @structured_branch_files_changed = $find_files_structured_branch->();
    is(
        [sort @structured_branch_files_changed],
        [sort @subject_url_files_changed],
        'The only difference between the two non-master branches is these files'
    );

    # Apple thinks Cougars and Pumas are different things; similarly, that
    # Panthers and Leopards are different things. They're not, so get rid of
    # the duplicates.
    git_ok(
        'Get rid of Mountain Lion, which is the same as a Puma',
        'rm',
        my $path_mountain_lion
            = File::Spec->catdir('Mountain Lion', 'subject_url')
    );
    git_ok('Get rid of Panther, which is the same as a Leopard',
        'rm',
        my $path_panther = File::Spec->catdir('Panther', 'subject_url')
    );
    git_ok('Commit this', 'commit', '--message', 'Remove redundant files');
    my @limited_subject_url_files_changed
        = grep { !/(Mountain Lion|Panther)/ } @subject_url_files_changed;
    is(
        [sort $find_files_structured_branch->()],
        [sort @limited_subject_url_files_changed],
        'Those two files are now gone from the list of changed files'
    );

    # Subsequently people complain that they can't find the subject URL
    # files, so add symlinks.
    my $path_puma = File::Spec->catdir('Puma', 'subject_url');
    my $path_leopard = File::Spec->catdir('Leopard', 'subject_url');
    symlink($path_puma,    $path_mountain_lion);
    symlink($path_leopard, $path_panther);
    git_ok('Add a symlink of puma -> mountain lion',
        'add', $path_mountain_lion);
    git_ok('Add a symlink of leopard -> panther',
        'add', $path_panther);
    git_ok('Push those symlink changes',
        'commit', '--message', 'Restore this dupes as symlinks');
    is(
        [sort $find_files_structured_branch->()],
        [sort @subject_url_files_changed],
        'We now have the complete set again'
    );

    # Merge master into the structured branch - everything goes ahead,
    # and only the summary file is marked as having changed, as git was clever
    # enough to realise that we'd moved it in this branch.
    git_ok('Switch back to the structured branch', 'checkout', 'structured');
    git_ok(
        'Merge master into the structured branch', 'merge', 'master',
        '--message', 'Merge master changes into structured'
    );
    @files_changed = $find_files_master->();
    ok(!(grep { /mac-os-versions/ } @files_changed),
        q{The old list of Mac OS versions still isn't mentioned});
    ok((grep { /summary/ } @files_changed),
        'The summary file is marked as having been changed');
    my $summary_contents = do {
        local $INPUT_RECORD_SEPARATOR = undef;
        open(my $fh, '<', 'summary');
        <$fh>
    };
    like($summary_contents, qr/Catalina/,
        'The summary file contains the newer Mac OS versions');

    # Merge the structured branch into master: now there are no differences.
    undef $mac_os_dir;
    git_ok('Switch to master', 'checkout', 'master');
    git_ok(
        'Merge the structured branch into master',
        'merge', 'structured',
        '--message', 'Make a structure of files'
    );
    git_ok('Switch to structured branch', 'checkout', 'structured');
    @files_changed = $find_files_master->();
    is([@files_changed], [],
        'There are no longer any changes compared to master');

    # In the more_links branch, though, there are still loads of changes
    # compared to master.
    git_ok('Switch to the more_links branch', 'checkout', 'more_links');
    @files_changed = $find_files_master->();
    is(
        [sort @files_changed],
        [sort @subject_url_files_changed],
        'Only the subject_url files have changed now'
    );
}

sub _mac_os_version_details {
    return (
        cats => [
            {
                codename     => 'Cheetah',
                release_date => '2001-03-24',
                os_url       => 'https://en.wikipedia.org/wiki/Mac_OS_X_10.0',
                subject_url  => 'https://en.wikipedia.org/wiki/Cheetah',
            },
            {
                codename     => 'Puma',
                release_date => '2001-09-25',
                os_url       => 'https://en.wikipedia.org/wiki/Mac_OS_X_10.1',
                subject_url  => 'https://en.wikipedia.org/wiki/Cougar',
            },
            {
                codename     => 'Jaguar',
                release_date => '2002-08-23',
                os_url       => 'https://en.wikipedia.org/wiki/Mac_OS_X_10.2',
                subject_url  => 'https://en.wikipedia.org/wiki/Jaguar',
            },
            {
                codename     => 'Panther',
                release_date => '2003-10-24',
                os_url => 'https://en.wikipedia.org/wiki/Mac_OS_X_Panther',
                subject_url => 'https://en.wikipedia.org/wiki/Leopard',
            },
            {
                codename     => 'Tiger',
                release_date => '2005-04-29',
                os_url      => 'https://en.wikipedia.org/wiki/Mac_OS_X_Tiger',
                subject_url => 'https://en.wikipedia.org/wiki/Tiger',
            },
            {
                codename     => 'Leopard',
                release_date => '2007-10-26',
                os_url => 'https://en.wikipedia.org/wiki/Mac_OS_X_Leopard',
                subject_url => 'https://en.wikipedia.org/wiki/Leopard',
            },
            {
                codename     => 'Snow Leopard',
                release_date => '2009-08-28',
                os_url =>
                    'https://en.wikipedia.org/wiki/Mac_OS_X_Snow_Leopard',
                subject_url => 'https://en.wikipedia.org/wiki/Snow_leopard',
            },
            {
                codename     => 'Lion',
                release_date => '2011-07-20',
                os_url       => 'https://en.wikipedia.org/wiki/Mac_OS_X_Lion',
                subject_url  => 'https://en.wikipedia.org/wiki/Lion',
            },
            {
                codename     => 'Mountain Lion',
                release_date => '2012-07-25',
                os_url => 'https://en.wikipedia.org/wiki/OS_X_Mountain_Lion',
                subject_url => 'https://en.wikipedia.org/wiki/Cougar',
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

sub dumper {
    local $Data::Dumper::Indent = 1;
    local $Data::Dumper::Sortkeys = 1;
    local $Data::Dumper::Terse = 1;
    return Dumper(@_);
}

