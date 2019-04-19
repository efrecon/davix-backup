FROM debian:stretch-slim


RUN \
    apt-get update && \
    apt-get install -y --no-install-recommends davix ca-certificates zip && \
    rm -rf /var/lib/apt/lists/*

# We might run with the following for better selection of releases
#FROM efrecon/davix
COPY *.sh /usr/local/bin/
ENTRYPOINT [ "/usr/local/bin/davix-backup.sh" ]