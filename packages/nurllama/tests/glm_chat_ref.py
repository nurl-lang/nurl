# Reference for nurllama's GLM chat styles: HF transformers'
# apply_chat_template with the model's own Jinja template.
#
# usage: glm_chat_ref.py <tokenizer-dir> <template.jinja> <messages.json>
#   prints the prompt for the messages plus the generation prompt, exactly,
#   with no newline added
import json
import sys

from transformers import AutoTokenizer

tok = AutoTokenizer.from_pretrained(sys.argv[1])
tpl = open(sys.argv[2], encoding="utf-8").read()
msgs = json.load(open(sys.argv[3], encoding="utf-8"))
out = tok.apply_chat_template(msgs, tokenize=False, add_generation_prompt=True, chat_template=tpl)
sys.stdout.buffer.write(out.encode("utf-8"))
