# Cloudflare Containers edellyttää että image on rekisterissä johon sillä
# on pääsy — `wrangler deploy` vetää tämän imagen (Docker Hub), uudelleen-
# tagittaa sen Cloudflaren managed-rekisteriin ja julkaisee sen.
#
# nurllang/nurl kuuntelee porttia 8000, joka on määritelty
# src/index.ts:n NurlContainer.defaultPort-kentässä.
#
# HUOM: api-deploy.yml -workflow ylikirjoittaa alla olevan tägin julkaistuun
# semveriin (esim. :v0.9.5) ennen deployta — tuotannon deploy ei käytä :latestiä.
# :latest jää vain paikallisen dockerpush.sh-fallbackin oletukseksi.
FROM docker.io/nurllang/nurl:latest
