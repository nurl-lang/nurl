# Cloudflare Containers edellyttää että image on rekisterissä johon sillä
# on pääsy — `wrangler deploy` vetää tämän imagen (Docker Hub), uudelleen-
# tagittaa sen Cloudflaren managed-rekisteriin ja julkaisee sen.
#
# Hindurable/nurl kuuntelee porttia 8000, joka on määritelty
# src/index.ts:n NurlContainer.defaultPort-kentässä.
FROM docker.io/hindurable/nurl:latest
