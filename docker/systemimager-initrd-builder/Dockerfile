FROM centos:7
MAINTAINER Brian Elliott Finley <brian@thefinleys.com>

# Things to make life easier if tweaking
RUN yum update -y
RUN yum install -y vim man git 
RUN yum install -y mlocate && updatedb

# Minimal commands needed for actual builds
RUN yum install -y dracut kernel make gcc gcc-c++ wget flex rsync
RUN yum install -y rpm-build gperf pam-devel quilt lzop glib2-devel PyXML glibc-static python-devel
RUN yum install -y e2fsprogs e2fsprogs-devel libuuid-devel ncurses-devel readline-devel 
RUN yum install -y parted kbd strace dosfstools kexec-tools btrfs-progs xfsprogs docbook-utils bc

# RUN cd /usr/src/systemimager && make initrd

