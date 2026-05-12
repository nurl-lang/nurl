docker build -t nurlapi -f nurlapi/Dockerfile .
docker run -p 8000:8000 nurlapi