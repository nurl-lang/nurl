# Changelog

## 0.1.1

`GrpcCall` is dropped automatically (`% Drop`), the call-failure path takes its error by `sink`, and the call table's getter/setter pair writes back with `mem_put_back` (NURL 0.67.0 ownership, #1141/#1142).

