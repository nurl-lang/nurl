import numpy as np, onnx
from onnx import helper, TensorProto, numpy_helper
import onnxruntime as ort, sys, os

def mlp(name, din, dh, dout, outdir, opset=13):
    rng = np.random.default_rng(42)
    W1 = rng.standard_normal((din, dh)).astype(np.float32) * 0.1
    b1 = rng.standard_normal((dh,)).astype(np.float32) * 0.1
    W2 = rng.standard_normal((dh, dout)).astype(np.float32) * 0.1
    b2 = rng.standard_normal((dout,)).astype(np.float32) * 0.1
    X = helper.make_tensor_value_info('X', TensorProto.FLOAT, [1, din])
    Y = helper.make_tensor_value_info('Y', TensorProto.FLOAT, [1, dout])
    inits = [numpy_helper.from_array(W1,'W1'), numpy_helper.from_array(b1,'b1'),
             numpy_helper.from_array(W2,'W2'), numpy_helper.from_array(b2,'b2')]
    nodes = [
        helper.make_node('Gemm', ['X','W1','b1'], ['h0'], alpha=1.0, beta=1.0, transB=0),
        helper.make_node('Relu', ['h0'], ['h1']),
        helper.make_node('Gemm', ['h1','W2','b2'], ['Y'], alpha=1.0, beta=1.0, transB=0),
    ]
    graph = helper.make_graph(nodes, name, [X], [Y], inits)
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid('', opset)])
    model.ir_version = 8
    onnx.checker.check_model(model)
    path = os.path.join(outdir, name+'.onnx')
    onnx.save(model, path)
    # reference run
    x = rng.standard_normal((1, din)).astype(np.float32)
    sess = ort.InferenceSession(path, providers=['CPUExecutionProvider'])
    y = sess.run(['Y'], {'X': x})[0].astype(np.float32)
    x.tofile(os.path.join(outdir, name+'.in.f32'))
    y.tofile(os.path.join(outdir, name+'.out.f32'))
    print(f'{name}: {din}->{dh}->{dout}  model={os.path.getsize(path)}B  y[:4]={y.ravel()[:4]}')
    return y

outdir = sys.argv[1]
mlp('tiny', 4, 8, 3, outdir)
mlp('mnist', 784, 128, 10, outdir)
