# containers/runner/supervisor/Dockerfile — keeps N ephemeral runners alive.
#
# The only container that holds the PAT and the host's Docker socket. Job
# code never runs here: it runs in the runner containers this one starts,
# which get neither.
FROM docker:cli

RUN apk add --no-cache bash coreutils curl jq

COPY supervisor.sh /usr/local/bin/nurl-runner-supervisor
RUN chmod 0755 /usr/local/bin/nurl-runner-supervisor

ENTRYPOINT ["/usr/local/bin/nurl-runner-supervisor"]
