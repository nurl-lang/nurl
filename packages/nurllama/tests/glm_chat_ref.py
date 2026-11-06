# Reference for nurllama's GLM chat styles: HF transformers'
# apply_chat_template with the model's own Jinja template.
#
# usage: glm_chat_ref.py <tokenizer-dir> <template.jinja> <messages.json>
#   <messages.json> is a message list, or a request body
#   {"messages": [...], "reasoning_effort": ..., "chat_template_kwargs": {...}}
#   whose switches go to the template as its variables (as vLLM passes
#   them). Prints the prompt plus the generation prompt, exactly, with no
#   newline added.
import json
import sys

from transformers import AutoTokenizer

tok = AutoTokenizer.from_pretrained(sys.argv[1])
tpl = open(sys.argv[2], encoding="utf-8").read()
body = json.load(open(sys.argv[3], encoding="utf-8"))
kwargs = {}
if isinstance(body, dict):
    msgs = body["messages"]
    if "reasoning_effort" in body:
        kwargs["reasoning_effort"] = body["reasoning_effort"]
    kwargs.update(body.get("chat_template_kwargs", {}))
else:
    msgs = body
out = tok.apply_chat_template(msgs, tokenize=False, add_generation_prompt=True, chat_template=tpl, **kwargs)
sys.stdout.buffer.write(out.encode("utf-8"))
