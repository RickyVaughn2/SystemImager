#  
#   Copyright (C) 2004-2015 Brian Elliott Finley
#
#   vi:set filetype=perl et ts=4 ai tw=0 number:
# 
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
# 
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
# 
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#

package SystemImager::UseYourOwnKernel;

use strict;
use File::Basename;
use SystemImager::Config qw($config);
use SystemImager::Common qw(which);
use File::Temp qw/ :mktemp /;


our $verbose;
our $is_mounted = 0;
our $fs_regexp = "(cramfs|ext2|ext3|reiserfs|xfs|jfs|cpio)";

#
# Usage: 
#       SystemImager::UseYourOwnKernel->create_uyok_initrd(
#           $arch, $my_modules, $custom_kernel, $custom_mod_dir,
#           $image, $destination, $ssh_key,
#           $authorized_keys, $local_cfg, $verbose);
#
sub create_uyok_initrd() {

        #
        #   Summary:
        #
        #   1) identify existing initrd on system
        #   2) unpack existing initrd into a staging directory
        #   3) add contents of SystemImager template directory into
        #      staging directory
        #   4) add additional binaries required for autoinstall into
        #      staging directory
        #   5) pack up the staging directory as a new initrd ready for
        #      use with the autoinstall client software.
        #

        my $module          = shift;
        my $arch            = shift;
        my $my_modules      = shift;
        my $custom_kernel   = shift;
        my $custom_mod_dir  = shift;
        my $image           = shift;
        my $destination     = shift;
        my $ssh_key         = shift;
        my $authorized_keys = shift;
        my $local_cfg       = shift;
        my $system_firmware = shift;
        my $firmware_dir    = shift;
        $verbose            = shift;

        use File::Copy;
        use File::Basename;
        use File::Path;

        my $cmd;
        my $file;

        my $boot_dir;
        if ($destination) {
            $boot_dir = $destination;
        } else {
            $boot_dir = '/usr/share/systemimager/boot';
        }


        #########################################################################
        #
        #   1) identify existing initrd on system
        #

        #
        # Determine kernel version
        #
        my $prefix = "/";
        my $uname_r;
        if ($custom_kernel) {
            $uname_r = _get_kernel_release($custom_kernel);

        } elsif ($image) {

            my $image_dir = $config->default_image_dir;

            $prefix = "$image_dir/$image";
            unless (-d $prefix) {
                print STDERR "ERROR: $image is not a valid image! use si_lsimage to see the list of available images.\n";
                print STDERR "Remember: the option --image can be used only on the image server.\n";
                exit(1);
            }

            # Autodetect custom kernel and modules directory in the image.
            $custom_kernel = _choose_kernel_file( '', $prefix );
            $uname_r = _get_kernel_release($custom_kernel);
            $custom_mod_dir = "$prefix/lib/modules/$uname_r";

        } else {
            $uname_r = get_uname_r();
        }

        #
        #   2) unpack existing initrd into a staging directory
        #

        #
        # Create temp dir
        #
        my $staging_dir = _mk_tmp_dir();

        # Set the cleanup handler.
        $SIG{__DIE__} = sub {
            my $msg = shift;
            if ($staging_dir) {
                if ($staging_dir =~ m/^\/tmp\/\.systemimager\.[0-9]+$/) {
                    system("rm -rf $staging_dir");
                }
            }
            die $msg;
        };

        #
        #   3) add contents of SystemImager template directory into staging directory
        #

        #
        # Copy SSH keys.
        #
        if ($ssh_key) {
            unless (-d "$staging_dir/root/.ssh/") {
                mkdir("$staging_dir/root/.ssh/", 0700) or
                    die("Couldn't create directory: $staging_dir/root/.ssh/!\n");
            }
            print "INFO: Including SSH private key: $ssh_key\n" if ($verbose);
            unless( copy($ssh_key, "$staging_dir/root/.ssh/") ) {
                die("Couldn't copy $ssh_key to $staging_dir/root/.ssh/!\n");
            }
        }
        if ($authorized_keys) {
            unless (-d "$staging_dir/root/.ssh/") {
                mkdir("$staging_dir/root/.ssh/", 0700) or
                    die("Couldn't create directory: $staging_dir/root/.ssh/!\n");
            }
            print "INFO: Including SSH authorized keys: $authorized_keys\n" if ($verbose);
            unless( copy($authorized_keys, "$staging_dir/root/.ssh/authorized_keys") ) {
                die("Couldn't copy $authorized_keys to $staging_dir/root/.ssh/authorized_keys!\n");
            }
        }

        #
        # Copy local.cfg
        #
        if ($local_cfg) {
            print "INFO: Including local.cfg into the initrd.img: $local_cfg\n" if ($verbose);
            unless (copy($local_cfg, "$staging_dir/local.cfg")) {
                die("Couldn't copy $local_cfg to $staging_dir/local.cfg!\n");
            }
        }

#XXX handle firmware via dracut
#
#   For now, we just use the modules and kernel (and firmware) already in the
#   system's initrd that we're starting from. -BEF-
#
#
#        #
#        # Copy /lib/firmware files to initrd if option --with-system-firmware is used
#        #
#        if($system_firmware) {
#            $firmware_dir="/lib/firmware" if(!$firmware_dir);
#            if ( -d $firmware_dir ) {
#                $cmd = qq(rsync -aLR /lib/firmware $staging_dir);
#                !system( $cmd ) or die( "Couldn't $cmd." );
#            }
#        }

        create_initrd_with_dracut($staging_dir, $boot_dir, $arch, $uname_r);
        _get_copy_of_kernel( $uname_r, $boot_dir, $custom_kernel );
        _record_arch( $boot_dir );

        !system( $cmd ) or die( "Couldn't $cmd." );
exit 1; #XXX
        return 1;
}


#
# give_missing_binaries_warning(\@list_of_binaries);
#
sub give_missing_binaries_warning($) {

    my $missing_binaries = shift;

    print qq/

WARNING: The following binaries could not be found on this machine, but we'll
assume they're filesystem related and that that's OK for now. ;-)  SystemImager
can deploy images using many different filesystems but most people only use one
or two.  If your autoinstall attempt fails, you may need to do one of the
following:

    a) install additional filesystem utilities on this machine
    b) change the filesystem type to be deployed in autoinstallscript.conf
       (see "man autoinstallscript.conf" for details)

/;
    foreach my $binary (@$missing_binaries) {
        print "  $binary\n";
    }
    print "\n";
    sleep 1;

    return 1;
}


sub create_initrd_with_dracut($$$$) {

    my $staging_dir     = shift;
    my $boot_dir        = shift;
    my $arch            = shift;
    my $uname_r         = shift;

    my $file;
    my @files;
    my %drivers_to_add;
    my %drivers_to_omit;
    my %binaries_to_include;
    my $cmd_line_width = 80;
    my $line;
    my $cmd;
    my $templateDir = "/usr/share/systemimager/boot/$arch/standard/initrd_template/";



    push @files, "/proc/modules";
    push @files, "/etc/systemimager/UYOK.kernel_modules_to_include";
    %drivers_to_add      = read_in_list_of_things(@files);

    $file = "/etc/systemimager/UYOK.kernel_modules_to_exclude";
    %drivers_to_omit     = read_in_list_of_things($file);

    $file = "/etc/systemimager/UYOK.binaries_to_include";
    %binaries_to_include = read_in_list_of_things($file);

    my @missing_required_binaries;
    my @missing_optional_binaries;
    foreach my $binary ( keys %binaries_to_include ) {
        if( ! which($binary) ) {
            if($binaries_to_include{$binary} eq 'required') {
                push(@missing_required_binaries, $binary);
            } else {
                push(@missing_optional_binaries, $binary);

                # Remove it from the list we'll try to include with dracut
                delete $binaries_to_include{$binary};
            }
        }
    }

    if( @missing_required_binaries ) {
        give_missing_binaries_warning(\@missing_required_binaries);
        print "The above binaries are required!\n";
        exit 7; #XXX make this more graceful
    }

    if( @missing_optional_binaries ) {
        give_missing_binaries_warning(\@missing_optional_binaries);
    }


    #
    #   Create dracut.conf file
    #
    my $dracut_conf = mktemp('/tmp/systemimager-dracut.conf.XXXX');
    open(DRACUT_CONF,">$dracut_conf") or die("Couldn't open $dracut_conf for writing.");

        print DRACUT_CONF qq(# SystemImager created dracut.conf file\n);
        print DRACUT_CONF qq(\n);
        print DRACUT_CONF qq(# Specific list of dracut modules to use\n);
        print DRACUT_CONF qq(dracutmodules+="base systemimager"\n);
        print DRACUT_CONF qq(\n);
        print DRACUT_CONF qq(# additional kernel modules to the default\n);

        #
        #   Kernel modules to add
        #
        foreach my $entry (sort keys %drivers_to_add) {
            print DRACUT_CONF qq(add_drivers+="$entry"\n);
        }

        #
        #   Kernel modules to omit
        #
        foreach my $entry (sort keys %drivers_to_omit) {
            print DRACUT_CONF qq(omit_drivers+="$entry"\n);
        }

        print DRACUT_CONF qq(\n);
        print DRACUT_CONF qq(# list of kernel filesystem modules to be included in the generic initramfs\n);
        print DRACUT_CONF qq(#filesystems+=""\n);
        print DRACUT_CONF qq(\n);
        print DRACUT_CONF qq(# build initrd only to boot current hardware\n);
        print DRACUT_CONF qq(#hostonly="yes"\n);
        print DRACUT_CONF qq(#\n);
        print DRACUT_CONF qq(\n);
        print DRACUT_CONF qq(# install local /etc/mdadm.conf\n);
        print DRACUT_CONF qq(mdadmconf="no"\n);
        print DRACUT_CONF qq(\n);
        print DRACUT_CONF qq(# install local /etc/lvm/lvm.conf\n);
        print DRACUT_CONF qq(lvmconf="no"\n);

    close(DRACUT_CONF);



    #
    #   Begin crafting command
    #   XXX handle --flavor -BEF-
    #
    $cmd  = qq(dracut --force --conf $dracut_conf \\\n);
        #$cmd .= qq( --verbose \\\n);    #XXX comment out this line prior to packaging

        #
        #   Binaries to install
        #
        $cmd .= qq( --install \\\n) if(%binaries_to_include);
        $line = qq(");  # single double-quote here is important
        foreach my $entry (sort keys %binaries_to_include) {
            # 4 spaces, plus current line, plus new entry
            if( (4 + (length $line) + (length $entry)) <= $cmd_line_width ) {
                $line .= qq($entry );
            } else {
                # Finish this line
                $line =~ s/ $//;
                $cmd .= qq(    $line \\\n);
                # and start a new one
                $line = qq($entry );
            }
        }
        # Finish the last line for this argument
        $line =~ s/ $//;
        $cmd .= qq(    $line" \\\n);    # single double-quote here is important

        $cmd .= qq( --include "$templateDir" / \\\n);
        $cmd .= qq(   $boot_dir/initrd.img  $uname_r\n);

    run_cmd($cmd, 1);
exit 1;


    return 1;
}


sub get_libs {
    
    my $binary = shift;

    my @libs;
    my $cmd = "ldd $binary";
    open(INPUT,"$cmd|") or die;
    while(<INPUT>) {
        if(m# => /#) {
            my($junk_a, $lib, $junk_c, $lib_file) = split(/\s+/, $_);
            chomp($lib_file);
            push(@libs, $lib_file);
        } elsif(m#not a dynamic executable#) {
            push(@libs, "not a dynamic executable");
        }
    }
    close(INPUT);

    if($verbose) {
#XXX       print "INFO: Found the following libraries required by $binary:\n";
#XXX       foreach my $lib (@libs) {
#XXX           print "  $lib\n";
#XXX       }
#XXX       print "\n";
    }

    return @libs;
}


sub _record_arch {

        my $boot_dir = shift;

        my $arch = _get_arch();
        my $file = $boot_dir . "/ARCH";
        open(FILE,">$file") or die("Couldn't open $file for writing $!");
                print FILE "$arch\n";
        close(FILE);

        return 1;
}


#
# Usage: my $arch = get_arch();
#
sub _get_arch {

    use POSIX;
    
    my $arch = (uname())[4];
    $arch =~ s/i.86/i386/;
    
        my $cpuinfo = "/proc/cpuinfo";
        
        #
        # On the PS3, /proc/cpuinfo has a line which reads (depending on kernel version):
        # platform        : PS3(PF)
        #
        open(CPUINFO,"<$cpuinfo") or die("Couldn't open $cpuinfo for reading");
        while(<CPUINFO>) {
            if ( m/PS3/ ) {
                $arch = "ppc64-ps3";
            }
        }
        close(CPUINFO);
    
    return $arch;
}


sub _get_copy_of_kernel($$) {

        my $uname_r       = shift;
        my $boot_dir      = shift;
        my $kernel_file   = shift;

        unless ($kernel_file) {
            $kernel_file = _choose_kernel_file( $uname_r );
        }
        unless( defined $kernel_file ) {
                print "I couldn't identify your kernel file.  Please try to use --kernel option.\n";
                exit 1;
        }

        print "INFO: Using kernel from:          $kernel_file\n" if( $verbose );

        my $new_kernel_file = $boot_dir . "/kernel";
        copy($kernel_file, $new_kernel_file) or die("Couldn't copy $kernel_file to $new_kernel_file: $!");
        _display_file_size("$new_kernel_file");

        return 1;
}

#
# Usage: my $is_this_file_a_kernel = is_kernel( $kernel );
#
sub is_kernel {

        # The goal here is to make reasonable effort to _eliminate_
        # files that are obviously _not_ kernels.  Any thing that passes
        # the elimination tests we assume is a kernel.
        #
        # Problem with trying to positively identify files that are kernels
        # is that different distros and different archs produce kernels that
        # look different to "file", and we cannot comprehensively know that
        # we've considered all possible resultant strings from kernels.
        #
        # Therefore, we should add elimination tests to this function whenever
        # we get a report of something passing as a kernel, that shouldn't.
        # -BEF-

        my $file = shift;
        my $filename = basename($file);

        #
        # Make sure it's binary
        if( ! -B $file ) { return undef; }
        #
        # and not a directory
        if( -d $file )   { return undef; }
        #
        # skip symlinks
        if( -l $file )   { return undef; }
        #
        # skip dot files
        if( $filename =~ /^\..*$/ )   { return undef; }
        #
        # skip *.bak files
        if( $filename =~ /\.bak$/ )   { return undef; }
        #
        # eliminate ramdisks
        if( $filename =~ m/initrd/ ) { return undef; }
        #
        # eliminate vmlinux files
        if( $filename =~ m/^vmlinux/ ) { return undef; }
        #
        # eliminate symvers files
        if( $filename =~ m/^symvers/ ) { return undef; }
        #
        # eliminate memtest
        if( $filename =~ m/^memtest/ ) { return undef; }
        #
        # eliminate message
        if( $filename =~ m/^message/ ) { return undef; }

        #
        # Get output from "file" for elimination by identification tests
        my $cmd = "file -bz $file";
        open(INPUT,"$cmd|") or die("Couldn't run $cmd to get INPUT");
                my ($input) = (<INPUT>);
                # eliminate cpio archives (eg. ramdisk)
                if( $input =~ m/cpio archive/ ) { return undef; }
                # eliminate cramfs files (eg. ramdisk)
                if( $input =~ m/Linux Compressed ROM File System data,/ ) { return undef; }
        close(INPUT);

        #
        # If we've made it down to here, then we'll assume it's a kernel. -BEF-
        return 1;
}


#
# Usage:
#       my $kernel_file = _choose_kernel_file( $uname_r, $image_dir );
#
sub _choose_kernel_file {

        my $uname_r = shift;
        my $image_dir = shift;
        $image_dir = '' if !($image_dir);
        my @dirs = ("$image_dir/boot", "$image_dir/");
        my @kernels;

        foreach my $dir (@dirs) {
                
                # 
                # Check each binary to see if it is a kernel file.  Preference given to the file with
                # the running kernel version, otherwise, the first available good kernel file is used.
                #
                opendir(DIR, $dir) || die("Can't opendir $dir: $!");
                        my @files = readdir(DIR);
                closedir DIR;

                foreach (@files) {
                        my $kernel = $_;
                        my $file = "$dir/$kernel";
                        if ( is_kernel($file) ) {
                                my $kernel_release = _get_kernel_release($file);
                                if ( defined($kernel_release) and ($kernel_release eq $uname_r) ) {
                                        return $file;
                                } else {
                                        push(@kernels, $file);
                                }
                        }
                }
        }
        # If cannot find kernel with name matching running version, return the first good one
        if (@kernels) {
            foreach my $file (@kernels) {
                my $kernel_release = _get_kernel_release($file);
                if (defined($kernel_release) and (-d "$image_dir/lib/modules/$kernel_release")) {
                    return $file;
                }
            }
        }

        return undef;
}


#
# Usage:
#       my $uname_r = _get_kernel_release( '/path/to/kernel/file' );
sub _get_kernel_release($) {

        my $file = shift;

        # the default tool
        my $cat = "cat";

        my $cmd = "gzip -l $file >/dev/null 2>&1";
        if( !system($cmd) ) {
                # It's gzip compressed.  Let's decompress it, man.
                $cat = "zcat";
        }

        my $uname_r;
        $cmd = "$cat $file";
        open(IN,"$cmd |") or die("Couldn't $cmd: $!");
        binmode(IN);
                # 
                # Example entries like what we're trying to match against in kernels:
                #       2.6.10bef1 (finley@mantis) #1 Tue Mar 1 00:37:55 CST 2005
                #       2.4.21.SuSE_273.bef1 (root@tg-c025) (gcc version 3.2.2) #1 SMP Mon Jan 24 11:55:28 CST 2005
                #       2.4.24 (root@mantis) #2 Fri Jan 16 19:51:43 CST 2004^
                #       2.4.19-mantis-2002.11.20 (root@mantis) #6 Tue Nov 19 15:15:43 CST 2002
                #       2.6.7-1-686 (dilinger@toaster.hq.voxel.net) #1 Thu Jul 8 05:36:53 EDT 2004
                #       2.6.22.5-31-default (geeko@buildhost) #1 SMP 2007/09/21 22:29:00 UTC
                #
                my $regex =
                #           | kernel version + build machine
                #           `---------------------------------------
                            '(((2\.[46])|(3\.\d{1,2}))\.\d{1,2}[\w.-]*) *\(.*@.*\) [#]\d+.*' .
                #
                #           | build date
                #           `---------------------------------------
                            '(\w{3} \w{3} \d{1,2})|(\d{4}\/\d{2}\/\d{2}) '.
                #
                #           | build time
                #           `---------------------------------------
                            '\d{2}:\d{2}:\d{2} \w{3,4}( \d{4})?';
                while(<IN>) {
                       # extract the `uname -r` string from the kernel file
                       if(m/$regex/o) {
                               $uname_r = $1;
                               last;
                       }
               }
        close(IN);

        return $uname_r;
}

#
# Usage:
#    my $is_this_file_a_initrd = is_initrd( $file, $kernel_release );
#
sub is_initrd
{
        # Try to detect if a file is a valid initrd that can be used to
        # boot the image - used by kexec stuff to generate a valid
        # configuration file for systemconfigurator
        # (/etc/systemconfig/systemconfig.conf).

        my $file = shift;
        my $kernel_release = shift;

        #
        # explicitly skip files without "initrd" in the filename
        unless ( $file =~ /initrd|initramfs/ ) { return undef; }
        #
        # Make sure it's binary
        if( ! -B $file ) { return undef; }
        #
        # and not a directory
        if( -d $file )   { return undef; }
        #
        # skip symlinks
        if( -l $file )   { return undef; }
        #
        # skip .bak files
        if( $file =~ /\.bak$/ )   { return undef; }

        # Get output from "file" for elimination by identification tests
        my $cmd = "file -zb $file";
        open(INPUT,"$cmd|") or die("Couldn't run $cmd to get INPUT");
                my ($input) = (<INPUT>);
                # eliminate vmlinux files
                if( $input =~ m/ELF (32|64)-bit [ML]SB/ ) { return undef; }
                # eliminate kernels
                if( $input =~ m/kernel/i ) { return undef; }
                # eliminate boot sectors
                if( $input =~ m/x86 boot sector/i ) { return undef; }
        close(INPUT);

        if ($kernel_release) {
            # Look for the kernel release into the initrd.
            foreach $cmd ('grep', 'zgrep') {
                chomp(my $rel_check = `$cmd -l "$kernel_release" $file 2>/dev/null`);
                if ($rel_check eq $file) {
                    return 1;
                }
            }
            # The kernel version string couldn't be found in the initrd, but if
            # the filename contains the kernel version probably it's the right
            # initrd to be used; i.e. if the kernel is statically built (no
            # loadable module support) the version string can't be found into
            # the initrd. -AR-
            if (((index($file, $kernel_release)) > 0) && ($file =~ /initrd/)) {
                return 1;
            }
        }

        return undef;
}


##
## Usage:
##       my $initrd_file = _choose_initrd_file( $boot_dir, $kernel_release );
##
#sub _choose_initrd_file
#{
#        # Try to detect a valid initrd that can be used together with a
#        # kernel release - this function is used by kexec stuff to
#        # generate a configuration file for systemconfigurator
#        # (/etc/systemconfig/systemconfig.conf)
# 
#        my $dir = shift;
#        my $kernel_release = shift;
#
#        opendir(DIR, $dir) || die("Can't opendir $dir: $!");
#        my @files = readdir(DIR);
#        closedir DIR;
#
#        foreach (@files) {
#                my $file = "$dir/$_";
#                if (is_initrd($file, $kernel_release)) {
#                        return $file;
#                }
#        }
#}


#
#       Usage: my $dir = _mk_tmp_dir();
#
sub _mk_tmp_dir() {

        my $count = 0;
        my $dir = "/tmp/.systemimager.";

        until( ! -e "${dir}${count}" ) {
                $count++;
        }
        mkdir("${dir}${count}", 0750) or die "$!";

        return "${dir}${count}";
}


sub get_uname_r {

        #
        # later, deal with this:
        #       
        #    --kernel FILE
        #
        #    identify kernel file
        #    extract uname-r info
        #
        my $kernel_version = `uname -r`;
        chomp $kernel_version;

        return $kernel_version;
}


#
#   Usage:  my %hash = read_list_of_things($file);
#           my %hash = read_list_of_things($file, $file2, $file3, etc.);
#           my %hash = read_list_of_things(@files);
#
#       Where:
#       - Each line that is not blank or a comment will be included in @array.
#       - Anything after the first space on a line gets stripped off
#
sub read_in_list_of_things() {

    my @files   = @_;

    my %things;

    foreach my $file (@files) {
        next if (! $file);
        if (-e $file) {
            open(FILE, "<$file") or die("Couldn't open $file for reading\n");
            while(<FILE>) {
                s/^\s+//;               # strip off leading spaces
                next if(m/^(#|\s|$)/);  # skip comments and empty lines
                chomp;

                my ($thing, $details) = split;

                if(! $details) { $details = 'none'; }
                $things{$thing} = $details;
            }
            close(FILE);
        } else {
            print STDERR qq(WARNING: $file doesn't exist!\n);
        }
    } 

    return %things;
}


#
#   my $uncompressed_initrd_size = get_uncompressed_initrd_size($initrd_file);
#
sub get_uncompressed_initrd_size($) {

        my $initrd = shift;

        my $size;
        if (-f $initrd) {
            $size = (`zcat $initrd | wc -c` + 10485760) / 1024;
        }

        return $size;
}


sub _display_file_size($) {

    my $file = shift;

    my $fileSize = (stat($file))[7];
    printf("INFO:  %.0f MB $file\n", $fileSize / 1024 / 1024);

    return 1;
}


#
# Usage:  
#       run_cmd("my shell command", 1, 1);
#
#       First argument:  the "command" to run.
#           Required.
#
#       Second argument: '1' to print command before running.
#           Defaults to "off".
#
#       Third argument:  '1' to print a newline after the command.
#           Defaults to "off".
#
sub run_cmd($$$) {

        my $cmd = shift;
        my $add_newline = shift;

        #if(!$verbose) {
        #        $cmd .= " >/dev/null 2>/dev/null";
        #}

        print "INFO: $cmd\n" if($verbose);
        !system($cmd) or die("FAILED: $cmd");
        print "\n" if($add_newline and $verbose);

        return 1;
}


1;

