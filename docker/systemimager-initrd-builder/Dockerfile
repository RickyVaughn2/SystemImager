FROM centos:7
MAINTAINER Brian Elliott Finley <brian@thefinleys.com>

# Things to make life easier if tweaking
RUN yum install vim -y

# Minimal commands needed for actual builds
RUN yum install -y \
    dracut \
    kernel 


# RUN cd /usr/src/systemimager && make initrd

