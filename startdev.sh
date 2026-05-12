docker build -f api/Dockerfile -t hindurable/nurl:latest .
docker run --rm -p 8000:8000 hindurable/nurl:latest