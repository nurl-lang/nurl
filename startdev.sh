docker build -f api/Dockerfile -t hindurable/nurl:latest .
docker run --rm -p 8001:8000 hindurable/nurl:latest