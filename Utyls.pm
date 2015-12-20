use MooseX::Declare;
use FindBin qw($Bin);
use lib "$Bin";

class Utyls {
    use Function::Parameters qw/:strict/;
    use Data::Dumper;
    use List::Util qw/first max maxstr min minstr reduce shuffle sum/;
    use DateTime;

    method slurp (Str $filename) {do {local (@ARGV, $/)= $filename; <>}}

    method slurp_array (Str $filename) {
        (map {s/[\r\n]+$//; $_} (do {local @ARGV= $filename; <>}))}

    method slurp_n_thaw (Str $filename) {$self->thaw($self->slurp($filename))}

    method spew (Str $filename, Str $data) {
        open(my $fh, '>', $filename) or die $! . " $filename";
        print $fh $data;
        close $fh;
        $data;
    }

    method freeze (Ref $data) {Dumper($data)}

    method thaw (Str $data) {eval('+' . substr($data, 8))}

    method freeze_n_spew (Str $filename, Ref $data) {
        $self->spew($filename, $self->freeze($data));
        $data;
    }

    method clone ($original) {$self->thaw($self->freeze($original))}

    method merge_hashes (@hashrefs) {
        my $result= +{};
        for my $hashref (@hashrefs) {
            for my $key (keys %$hashref) {
                $result->{$key}= $hashref->{$key}}}
        $result;
    }

    method join_paths (@parts) {
        # Given components of a file path, this method will combine the
        # components to create a file path, inserting or removing '/'
        # characters where necessary.
        my $ds= sum map {defined($_) || 0} @parts;
        unless(@parts > 1 && @parts == $ds) {
            die "You must provide at least 2 strings. You provided " .
            join(", ", map {"'$_'"} @parts) . " => $ds"}
        my @paths;
        push @paths, map {/^(.+)\/?$/; $1} shift @parts;
        push @paths, map {/^\/*(.+)\/?$/; $1} @parts;
        my $path= join('/', grep {defined $_ && $_ ne ''} @paths);
        $path =~ s/([^:])\/\//$1\//g;
        $path
    }

    method filename_only (Str $filename) {
        # Given an absolute filename, this method will return the filename
        # itself, without the path information.
        $filename=~ /([^\/\\]+)$/;
        defined($1) ? $1 : ''
    }

    method path_only (Str $filename) {
        $filename =~ /(.+)\/[^\/]+$/; $1
    }

    method replace_extension (Str $filename, Str $new_extension) {
        my $new_filename= '';
        $new_extension= '' unless defined($new_extension);
        $new_extension= substr($new_extension, 1) if $new_extension =~ /^\./;
        $new_filename= $1 if $filename =~ /^(.*)\.[^. ]+$/;
        if ($new_filename ne '' && $new_extension ne '') {
            $new_filename.= ".$new_extension";
        }
        $new_filename= $filename if $new_filename eq '';
        $new_filename
    }

    method split_n_trim (Str|RegexpRef $separator, Str $string) {
        # Like split, but returns an array in which each element is trimed
        # of beginning and ending whitespace. The new array also excludes
        # empty strings.
        grep {$_ ne ''}
        map {$_=~ s/^\s+|\s+$//sg; $_}
        split $separator, $string
    }

    method pull_file (
        Str $remote_host,
        Str $remote_file,
        Str $local_file,
        Str :$user = 'ubuntu',
        Str :$password = '',
        Str|ArrayRef :$keys = '',
        Bool :$file_contents = 0,
        Bool :$dry_run = 0)
    {
        my $remote= "$remote_host:$remote_file";
        my $env= $password
            ? ('RSYNC_PASSWORD="' . $password . '" ')
            : '';
        my $ssh= $self->ssh('', user => $user, keys => $keys);
        my $rsync= "${env}rsync -v -e '$ssh' $remote $local_file";
        my $result= +{
            command => $rsync,
            remote_path => $remote,
            local_path => $local_file,
        };
        return $result if $dry_run;
        unlink $local_file if -f $local_file;
        my $output= `$rsync 2>&1`;
        my $error= $?;
        $result->{output}= $output;
        $result->{error}= $error;
        if($file_contents) {
            $result->{file_contents}= $self->slurp($local_file)}
        $result;
    }

    method ssh (
        Str $remote_host,
        Str :$user = 'ubuntu',
        Str|ArrayRef :$keys = ''
    ) {
        my @keys= map {"-i $_"} grep {$_} (ref($keys) ? @$keys : ($keys));
        'ssh ' . join(
            ' ', (@keys, "-l $user",
                  '-o UserKnownHostsFile=/dev/null',
                  '-o StrictHostKeyChecking=no',
                  $remote_host));
    }

    method remote_command (
        Str $remote_host,
        Str $command,
        Str :$user = 'ubuntu',
        Str|ArrayRef :$keys = '',
        Bool :$debug = 0
    ) {
        my $ssh= $self->ssh(
            $remote_host, user => $user, keys => $keys
        ) . " '$command'";
        my $output= $debug ? `$ssh` : `$ssh 2>/dev/null`;
        my $result= +{
            command => $ssh,
            output => (defined($output) ? $output : '')};
        $result->{exit}= $? >> 8;
        $result;
    }

    method remote_file_exists (
        Str $remote_host,
        Str $remote_file,
        Str :$user = 'ubuntu',
        Str|ArrayRef :$keys = '',
        Bool :$sudo = 0
    ) {
        my $exists= $self->remote_command(
            $remote_host,
            (($sudo ? 'sudo ' : '') . "ls '$remote_file'"),
            user => $user,
            keys => $keys);
        !$exists->{exit};
    }

    method remote_directory_exists (
        Str $remote_host,
        Str $remote_file,
        Str :$user = 'ubuntu',
        Str|ArrayRef :$keys = '',
        Bool :$sudo = 0
    ) {
        my $exists= $self->remote_command(
            $remote_host,
            (($sudo ? 'sudo ' : '') . "file '$remote_file'"),
            user => $user,
            keys => $keys);
        $exists->{output} =~ /directory\s*$/;
    }

    method delete_remote_file (
        Str $remote_host,
        Str $remote_file,
        Str :$user = 'ubuntu',
        Str|ArrayRef :$keys = ''
    ) {
        if($self->remote_file_exists(
            $remote_host, $remote_file, user => $user, keys => $keys)) {
            $self->remote_command(
                $remote_host, "rm '$remote_file'",
                user => $user, keys => $keys)}
        return;
    }

    method push_file (
        Str $local_file,
        Str $remote_host,
        Str $remote_directory,
        Str :$user = 'ubuntu',
        Str :$password = '',
        Str|ArrayRef :$keys = '',
        Bool :$dry_run = 0)
    {
        my $remote= "$remote_host:$remote_directory";
        my $remote_file= $self->join_paths($remote_directory, $local_file);
        my $env= $password
            ? ('RSYNC_PASSWORD="' . $password . '" ')
            : '';
        my $ssh= $self->ssh('', user => $user, keys => $keys);
        my $rsync= "${env}rsync -v -e '$ssh' $local_file $remote";
        my $result= +{
            command => $rsync,
            remote_path => $remote,
            local_path => $local_file,
            error => '',
            exit => '',
        };
        return $result if $dry_run;
        if(
            $self->remote_file_exists(
                $remote_host, $remote_file, keys => $keys)
        ) {
            $result->{delete}= $self->remote_command(
                $remote_host, "rm $remote_file",
                user => $user, keys => $keys);
            $result->{error}= $result->{delete}->{error};
            return $result if $result->{error};
        }
        my $output= `$rsync 2>&1`;
        $result->{exit}= $? >> 8;
        $result->{error}= $result->{exit}
            ? "Error while pushing file: $output"
            : '';
        $result;
    }

    method move_remote_file (
        Str $remote_host,
        Str $source,
        Str $destination,
        Str :$user = 'ubuntu',
        Str :$password = '',
        Str|ArrayRef :$keys = '',
        Bool :$sudo = 0)
    {
        my $cmd= ($sudo ? 'sudo ' : '') . "mv $source $destination";
        $self->remote_command($remote_host, $cmd, user => $user, keys => $keys);
    }

    method copy_remote_file (
        Str $remote_host,
        Str $source,
        Str $destination,
        Str :$user = 'ubuntu',
        Str :$password = '',
        Str|ArrayRef :$keys = '',
        Bool :$sudo = 0)
    {
        my $cmd= ($sudo ? 'sudo ' : '') . "cp $source $destination";
        $self->remote_command($remote_host, $cmd, user => $user, keys => $keys);
    }

    method create_remote_directory (
        Str $remote_host,
        Str $remote_directory,
        Str :$user = 'ubuntu',
        Str :$password = '',
        Str|ArrayRef :$keys = '',
        Bool :$sudo = 0)
    {
        unless(
            $self->remote_directory_exists(
                $remote_host, $remote_directory,
                user => $user, keys => $keys,
                sudo => $sudo)
        ) {
            my $cmd= ($sudo ? 'sudo ' : '') . "mkdir $remote_directory";
            $self->remote_command(
                $remote_host, $cmd, user => $user, keys => $keys);
        }
        return;
    }

    method delete_remote_directory (
        Str $remote_host,
        Str $remote_directory,
        Str :$user = 'ubuntu',
        Str :$password = '',
        Str|ArrayRef :$keys = '',
        Bool :$sudo = 0)
    {
        if(
            $self->remote_directory_exists(
                $remote_host, $remote_directory,
                user => $user, keys => $keys,
                sudo => $sudo)
        ) {
            my $cmd= ($sudo ? 'sudo ' : '') . "rm -Rf $remote_directory";
            return $self->remote_command(
                $remote_host, $cmd, user => $user, keys => $keys);
        }
        return;
    }

    method safe_push_move (
        Str $local_file,
        Str $remote_host,
        Str $remote_file,
        Str :$remote_backup_dir = '/home/ubuntu/config-backups',
        Str :$user = 'ubuntu',
        Str :$password = '',
        Str|ArrayRef :$keys = '',
        Bool :$sudo = 0
    ) {
        my $result;

        # Make sure that the remote_backup_dir exists
        $self->create_remote_directory(
            $remote_host,
            $remote_backup_dir,
            user => $user,
            keys => $keys);

        # Backup the remote file that we're going to replace
        if(
            $self->remote_file_exists(
                $remote_host, $remote_file,
                user => $user, keys => $keys)
        ) {
            my $dt= DateTime->now;
            my $backup= $self->join_paths(
                $remote_backup_dir,
                sprintf("%s.%s-%s.bak",
                        $self->filename_only($remote_file),
                        $dt->ymd(''), $dt->hms('')));
            $result= $self->copy_remote_file(
                $remote_host, $remote_file, $backup,
                user => $user, keys => $keys, sudo => $sudo);
            return $result if $result->{exit};
        }

        # Push the new file to /home/ubuntu/config-backups
        my $stage_path= $self->join_paths(
            $remote_backup_dir,
            $self->filename_only($remote_file));
        $self->delete_remote_file(
            $remote_host, $stage_path, user => $user, keys => $keys);
        $result= $self->push_file(
            $local_file, $remote_host, $remote_backup_dir,
            user => $user, keys => $keys);
        return $result if $result->{exit};

        # Copy the new file to its final destination
        $result= $self->move_remote_file(
            $remote_host, $stage_path, $remote_file,
            user => $user, keys => $keys, sudo => $sudo);
        return $result if $result->{exit};
        return;
    }

    method log_format (@messages) {
        DateTime->now->datetime() . ' ' . join('', @messages) . "\n";
    }

    method with_retries (
        Int :$tries = 3,
        Int :$sleep = 1.0,
        Int :$sleep_multiplier = 3.0,
        CodeRef :$logger = sub {},
        Str :$description,
        CodeRef :$action)
    {
        my $result;
        while($tries--) {
            $result= $action->();
            last if $result;
            $logger->("FAILED: $description");
            last unless $tries;
            $logger->("Will try again in $sleep seconds");
            sleep $sleep;
            $sleep*= $sleep_multiplier;
        }
        $result;
    }

#
# Usage: $value= $u->pluck($merchant_customer, qw/email address/);
#
# Purpose: Does roughly the same as the following code:
#
#     if(
#         $merchant_customer
#         && $merchant_customer->email
#         && $merchant_customer->email->address
#     ) {
#         $value= $merchant_customer->email->address
#     }
#     else {
#         $value= undef;
#     }
#
# But, in addition to working for objects with methods, the pluck
# function works generally with any nested data structures and
# is able to tell apart methods, hash keys, and array indexes.
#
# Returns: The value at the specified location or undef if the value
# doesn't exist or if the location doesn't exist.
#
# Parameters:
#     * $obj: The object or nested data structure
#     * @path: The path within the object to the location that
#       contains the value you want
#
    method pluck (Item $obj, Item $default, @path) {
        return $default unless defined($obj);
        my ($p, $q);
        eval {
            while(defined($p= shift @path)) {
                if(ref($obj) eq 'HASH' && exists $obj->{$p}) {
                    $obj= $obj->{$p}; next}
                if(
                    ref($obj) eq 'ARRAY'
                    && $p =~ /^[0-9]+$/ && defined $obj->[$p]
                ) {
                    $obj= $obj->[$p]; next}
                if(ref($obj) && ($q= $obj->$p)) {
                    $obj= $q; next}
                $obj= $default;
                last;
            }
        };
        $@ ? (ref($default) eq 'CODE' ? $default->($@) : $default) : $obj;
    }

}
