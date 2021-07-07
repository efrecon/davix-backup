FROM efrecon/davix:0.7.6
RUN \
    apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates zip && \
    rm -rf /var/lib/apt/lists/*

COPY *.sh /usr/local/bin/
ENTRYPOINT [ "/usr/local/bin/davix-backup.sh" ]
