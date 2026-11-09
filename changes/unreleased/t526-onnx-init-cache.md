### Performance

- **onnx keeps a graph's weights on the device from run to run** (Agora #526; onnx 0.13.0, and yoloe, map-anything, yoloe-demo and objdet for the new floor). Every run uploaded each FLOAT initializer again: 46 MB a frame for YOLOE-v8s-seg, half the time of a warm run. A warm 640×640 frame now takes 11.0 ms instead of 22.4 ms on an RTX 4090, with identical output and the same peak memory. The engine keys the kept copies on a graph's new identity (`OGraph.gid`) and lets them go before a different graph uploads its own.
