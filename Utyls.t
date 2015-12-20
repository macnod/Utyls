use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../../perl/";
use Data::Dumper;
use strict;
use warnings;

use_ok('Utyls');

my $u= Utyls->new;
my $keys= '/home/ubuntu/.ssh/eroskey-x.pem';
my $remote_host= 'cache-tools.erosnow.info';
ok($u, 'Utyls instantiates');
like($u->slurp("$Bin/Utyls.t"), qr/use_ok\('Utyls'\)/, 'slurp works');
cmp_ok(($u->slurp_array("$Bin/Utyls.t"))[0], 'eq', 'use Test::More;',
        'slurp_array works');
my $string= time;
cmp_ok($u->spew('/tmp/hello.txt', $string), 'eq', $string,
       'spew works (out)');
cmp_ok($u->slurp('/tmp/hello.txt'), 'eq', $string,
       'spew works (in)');
my $ref= +{one => 1};
cmp_ok($u->freeze($ref), 'eq', Dumper($ref),
       'freeze works');
is_deeply($u->thaw($u->freeze($ref)), $ref, 'thaw woks');
unlink '/tmp/hello.txt';
is_deeply($u->freeze_n_spew('/tmp/hello.txt', $ref), $ref,
          'freeze_n_spew works (1)');
ok(-f '/tmp/hello.txt', 'freeze_n_spew works (2)');
is_deeply($u->slurp_n_thaw('/tmp/hello.txt'), $ref,
          'slurp_n_thaw works');
my $ref_clone= $u->clone($ref);
is_deeply($ref, $ref_clone, 'clone works (1)');
$ref_clone->{one}= 2;
isnt($ref->{one}, $ref_clone, 'clone works (2)');
$ref->{two}= 2;
is_deeply($u->merge_hashes($ref, $ref_clone), +{one => 2, two => 2},
          'merge_hashes works (1)');
$ref_clone->{two}= 3;
my $merged= $u->merge_hashes($ref_clone, $ref);
is($merged->{two}, 2, 'merge_hashes works (2)');
$merged= $u->merge_hashes($ref, $ref_clone);
is($merged->{two}, 3, 'merge_hashes works (3)');
is($u->join_paths('/home/ubuntu', 'hello.txt'), '/home/ubuntu/hello.txt',
   'join_paths works');
is($u->filename_only('/home/ubuntu/hello.txt'), 'hello.txt',
   'filename_only works');
is($u->path_only('/home/ubuntu/hello.txt'), '/home/ubuntu',
   'path_only works');
is($u->replace_extension('/home/ubuntu/hello.txt', '.dat'),
   '/home/ubuntu/hello.dat', 'replace_extension works');
is_deeply(+[$u->split_n_trim(',', 'one, two, three')],
          +['one', 'two', 'three'],
          'split_n_trim works');
unlink '/tmp/hello.txt' if -f '/tmp/hello.txt';
my $result= $u->pull_file(
    'cache-tools.erosnow.info',
    '/home/ubuntu/tests/hello.txt',
    '/tmp/hello.txt',
    keys => $keys,
);
if(!ok(!$result->{error}, 'pull_file works (1)')) {
    diag Dumper($result);
}
ok(-f '/tmp/hello.txt', 'pull_file works (2)');
is($u->slurp('/tmp/hello.txt'), "Hello World\n",
   'pull_file works (3)');
is(
    $u->pull_file(
        'cache-tools.erosnow.info',
        '/home/ubuntu/tests/hello.txt',
        '/tmp/hello.txt',
        keys => $keys,
        file_contents => 1)->{file_contents},
    "Hello World\n",
    "pull_file_works (4)");
is(
    $u->ssh($remote_host, keys => $keys),
    "ssh -i $keys -l ubuntu "
        . '-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no '
        . $remote_host,
    'ssh works');
$result= $u->remote_command($remote_host, 'echo -n hello', keys => $keys);
is($result->{output}, 'hello', 'remote_command works');
$u->delete_remote_file($remote_host, '/tmp/good-bye.txt', keys => $keys);
ok(!$u->remote_file_exists($remote_host, '/tmp/good-bye.txt', keys => $keys),
   "remote_file_exists works (1)");
$u->spew("/tmp/good-bye.txt", "Good-bye World") unless -f "/tmp/good-bye.txt";
$result= $u->push_file(
    "/tmp/good-bye.txt",
    $remote_host,
    "/tmp",
    keys => $keys);
unless(ok(!$result->{exit}, 'push_file works (1)')) {
    diag Dumper($result);
}
ok($u->remote_file_exists(
    $remote_host, '/tmp/good-bye.txt', keys => $keys),
    'remote_file_exists works (2); push_file works (2)');
$result= $u->move_remote_file(
    $remote_host, '/tmp/good-bye.txt', '/tmp/good-bye-1.txt', keys => $keys);
ok(!$result->{exit}, 'move_remote_file works (1)');
ok(!$u->remote_file_exists($remote_host, '/tmp/good-bye.txt', keys => $keys),
   'move_remote_file works (2)');
ok($u->remote_file_exists($remote_host, '/tmp/good-bye-1.txt', keys => $keys),
   'move_remote_file works (3)');
$u->delete_remote_file($remote_host, '/tmp/good-bye-1.txt', keys => $keys);
ok($u->remote_directory_exists($remote_host, '/tmp', keys => $keys),
   'remote_directory_exists works (1)');
my $time= time;
$u->create_remote_directory($remote_host, "/tmp/$time", keys => $keys);
ok($u->remote_directory_exists($remote_host, "/tmp/$time", keys => $keys),
   'create_remote_directory works (1)');
$u->create_remote_directory($remote_host, "/tmp/$time", keys => $keys);
ok($u->remote_directory_exists($remote_host, "/tmp/$time", keys => $keys),
   'create_remote_directory works (2)');
$u->delete_remote_directory($remote_host, "/tmp/$time", keys => $keys);
ok(!$u->remote_directory_exists($remote_host, "/tmp/$time", keys => $keys),
   'create_remote_directory works (3); delete_remote_directory works (1)');
my $remote_config_dir= "/tmp/config-" . time;
my $remote_backup_dir= "/tmp/backup-" . time;
my $config1= '/tmp/config1.txt';
my $config2= '/tmp/config2.txt';
$u->create_remote_directory(
    $remote_host, $remote_config_dir, keys => $keys, sudo => 1);
$u->create_remote_directory($remote_host, $remote_backup_dir, keys => $keys);
$u->spew($config1, "one");
$u->spew($config2, "two");
$u->push_file($config1, $remote_host, $remote_backup_dir, keys => $keys);
$u->move_remote_file(
    $remote_host,
    $u->join_paths($remote_backup_dir, $u->filename_only($config1)),
    $u->join_paths($remote_config_dir, $u->filename_only($config1)),
    keys => $keys, sudo => 1);
$result= $u->pull_file(
    $remote_host,
    $u->join_paths($remote_config_dir, $u->filename_only($config1)),
    $config1,
    keys => $keys, file_contents => 1);
is($result->{file_contents}, 'one', "installed $config1");
$u->safe_push_move(
    $config2,
    $remote_host,
    $u->join_paths($remote_config_dir, $u->filename_only($config2)),
    remote_backup_dir => $remote_backup_dir, keys => $keys, sudo => 1);
$result= $u->pull_file(
    $remote_host,
    $u->join_paths($remote_config_dir, $u->filename_only($config2)),
    $config2,
    keys => $keys, file_contents => 1);
is($result->{file_contents}, 'two', "safe_push_move works");
unlink $config1;
unlink $config2;
$u->delete_remote_directory(
    $remote_host, $remote_config_dir, keys => $keys, sudo => 1);
$u->delete_remote_directory($remote_host, $remote_backup_dir, keys => $keys);
ok(!$u->remote_directory_exists(
    $remote_host, $remote_backup_dir, keys => $keys),
   "clean up remote directory $remote_backup_dir");
ok(!$u->remote_directory_exists(
    $remote_host, $remote_config_dir, keys => $keys),
   "clean up remote directory $remote_config_dir");
done_testing();
