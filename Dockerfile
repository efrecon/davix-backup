# We might run with the following for debian-default
#FROM debian:stretch-slim


#RUN \
#    apt-get update && \
#    apt-get install -y --no-install-recommends davix ca-certificates zip && \
#    rm -rf /var/lib/apt/lists/*

FROM efrecon/davix
COPY *.sh /usr/local/bin/
ENTRYPOINT [ "/usr/local/bin/davix-backup.sh" ]
