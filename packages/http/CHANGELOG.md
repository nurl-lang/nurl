# Changelog

## 0.6.2

Closures are no longer freed by hand: the router's handlers and the HTTP/3 thread body are owned by whatever holds them (NURL 0.67.0 closure ownership, #1141).

