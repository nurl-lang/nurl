# Check tests/qwen35_ref.py against HF transformers' own Qwen3_5 model on the
# original checkpoint — the reference is only as good as its reading of the
# GGUF (the [q | gate] interleave, the qkv split, the conv layout, ssm_a's
# sign), and this is where that reading is proven rather than assumed.
#
# The GGUF is quantised (Q8_0) and the checkpoint is bf16, run here in f32,
# so the logits are compared by agreement (argmax, top-5, correlation), not
# bit for bit: tests/qwen35_test.sh holds nurllama to the reference exactly.
#
# usage: qwen35_hf_check.py <model.gguf> <hf checkpoint dir> "<prompt>"
import sys
import numpy as np
import torch
from transformers import AutoTokenizer, AutoModelForImageTextToText
import qwen35_ref as ref

gguf, hfdir, prompt = sys.argv[1], sys.argv[2], sys.argv[3]
tok = AutoTokenizer.from_pretrained(hfdir)
ids = tok(prompt)['input_ids']
if ids and isinstance(ids[0], list):
    ids = ids[0]
assert ids, 'the tokenizer gave no ids'
model = AutoModelForImageTextToText.from_pretrained(hfdir, dtype=torch.float32)
model.eval()
with torch.no_grad():
    hf = model(input_ids=torch.tensor([ids], dtype=torch.long)).logits[0, -1].float().numpy()

kvs, tens = ref.load(gguf)
m = ref.Qwen35(kvs, tens)
for pos, t in enumerate(ids):
    ours = m.step(t, pos)
ours = ours[:hf.shape[0]]

r = np.corrcoef(hf, ours)[0, 1]
top_hf, top_ref = list(np.argsort(-hf)[:5]), list(np.argsort(-ours)[:5])
print('ids', ids)
print('argmax hf %d ref %d' % (hf.argmax(), ours.argmax()))
print('top5 hf ', top_hf, [tok.decode([i]) for i in top_hf])
print('top5 ref', top_ref, [tok.decode([i]) for i in top_ref])
print('correlation %.6f, max |delta| %.4f over a span of %.2f' % (r, np.abs(hf - ours).max(), hf.max() - hf.min()))
ok = hf.argmax() == ours.argmax() and r > 0.99 and len(set(top_hf) & set(top_ref)) >= 4
print('OK' if ok else 'MISMATCH')
sys.exit(0 if ok else 1)
