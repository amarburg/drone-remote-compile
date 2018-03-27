FROM alpine:3.4
MAINTAINER Aaron Marburg <amarburg@uw.edu>

RUN apk add --no-cache ca-certificates bash openssh-client rsync
COPY remote.sh /usr/local/

VOLUME /root/keys

WORKDIR /root
ENTRYPOINT ["/usr/local/remote.sh"]
