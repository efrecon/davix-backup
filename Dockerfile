FROM debian:stretch-slim


RUN \
    apt-get update && \
    apt-get install -y --no-install-recommends davix ca-certificates && \
    rm -rf /var/lib/apt/lists/*

#FROM efrecon/davix
COPY *.sh /usr/local/bin/
ENTRYPOINT [ "/usr/local/bin/davix-backup.sh" ]