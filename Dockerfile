# We might run with the following for debian-default
#FROM debian:stretch-slim


FROM efrecon/davix
RUN \
    apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates zip && \
    rm -rf /var/lib/apt/lists/*

COPY *.sh /usr/local/bin/
ENTRYPOINT [ "/usr/local/bin/davix-backup.sh" ]
