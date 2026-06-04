docker build -f nurlapi/Dockerfile -t nurllang/nurl:latest .
docker run --rm -p 8000:8000 nurllang/nurl:latest
