# Independent numpy reference for the llama forward pass, reading GGUF directly.
import struct, sys
import numpy as np

def read_gguf(path):
    d=open(path,'rb').read(); off=8
    nt,nkv=struct.unpack_from('<QQ',d,off); off+=16
    kvs={}; tens={}
    def rs(off):
        n=struct.unpack_from('<Q',d,off)[0]; off+=8
        return d[off:off+n], off+n
    for _ in range(nkv):
        k,off=rs(off); vt=struct.unpack_from('<I',d,off)[0]; off+=4
        if vt==8: v,off=rs(off)
        elif vt==9:
            at=struct.unpack_from('<I',d,off)[0]; off+=4
            cnt=struct.unpack_from('<Q',d,off)[0]; off+=8
            v=[]
            for _ in range(cnt):
                if at==8: e,off=rs(off); v.append(e)
                elif at==6: v.append(struct.unpack_from('<f',d,off)[0]); off+=4
                elif at==5: v.append(struct.unpack_from('<i',d,off)[0]); off+=4
                elif at==4: v.append(struct.unpack_from('<I',d,off)[0]); off+=4
                else: raise Exception('at')
        elif vt==4: v=struct.unpack_from('<I',d,off)[0]; off+=4
        elif vt==5: v=struct.unpack_from('<i',d,off)[0]; off+=4
        elif vt==6: v=struct.unpack_from('<f',d,off)[0]; off+=4
        elif vt==7: v=d[off]; off+=1
        elif vt in (10,11): v=struct.unpack_from('<q',d,off)[0]; off+=8
        else: raise Exception('vt')
        kvs[k.decode()]=v
    infos=[]
    for _ in range(nt):
        nm,off=rs(off); nd=struct.unpack_from('<I',d,off)[0]; off+=4
        dims=list(struct.unpack_from('<%dQ'%nd,d,off)); off+=8*nd
        ty=struct.unpack_from('<I',d,off)[0]; off+=4
        rel=struct.unpack_from('<Q',d,off)[0]; off+=8
        infos.append((nm.decode(),dims,ty,rel))
    align=kvs.get('general.alignment',32)
    doff=(off+align-1)//align*align
    for nm,dims,ty,rel in infos:
        ne=int(np.prod(dims))
        assert ty==0, 'F32 only in the reference'
        a=np.frombuffer(d,dtype='<f4',count=ne,offset=doff+rel)
        # ggml ne0 fastest → numpy shape reversed
        tens[nm]=a.reshape(list(reversed(dims)))
    return kvs,tens

kvs,tens=read_gguf(sys.argv[1])
ids=[int(x) for x in sys.argv[2].split()]
n_embd=kvs['llama.embedding_length']; n_layer=kvs['llama.block_count']
n_head=kvs['llama.attention.head_count']; n_kv=kvs['llama.attention.head_count_kv']
eps=kvs['llama.attention.layer_norm_rms_epsilon']
rope_dim=kvs.get('llama.rope.dimension_count', n_embd//n_head)
base=kvs.get('llama.rope.freq_base',10000.0)
hd=n_embd//n_head

f32=np.float32
def rms(x,w):
    x=x.astype(f32)
    inv=f32(1.0)/np.sqrt(np.mean(x*x,dtype=f32)+f32(eps))
    return (x*inv*w).astype(f32)

def rope(v,nh,pos):
    v=v.reshape(nh,hd).copy()
    for j in range(rope_dim//2):
        th=f32(pos)*f32(base)**f32(-2.0*j/rope_dim)
        c,s=np.cos(th,dtype=f32),np.sin(th,dtype=f32)
        a,b=v[:,2*j].copy(),v[:,2*j+1].copy()
        v[:,2*j]=a*c-b*s; v[:,2*j+1]=a*s+b*c
    return v.reshape(nh*hd)

K=[np.zeros((0,n_kv*hd),dtype=f32) for _ in range(n_layer)]
V=[np.zeros((0,n_kv*hd),dtype=f32) for _ in range(n_layer)]
logits=None
for pos,tok in enumerate(ids):
    x=tens['token_embd.weight'][tok].astype(f32)
    for L in range(n_layer):
        xn=rms(x,tens['blk.%d.attn_norm.weight'%L])
        q=(tens['blk.%d.attn_q.weight'%L]@xn).astype(f32)
        k=(tens['blk.%d.attn_k.weight'%L]@xn).astype(f32)
        v=(tens['blk.%d.attn_v.weight'%L]@xn).astype(f32)
        q=rope(q,n_head,pos); k=rope(k,n_kv,pos)
        K[L]=np.vstack([K[L],k]); V[L]=np.vstack([V[L],v])
        out=np.zeros(n_embd,dtype=f32)
        for h in range(n_head):
            kh=h//(n_head//n_kv)
            qh=q[h*hd:(h+1)*hd]
            ks=K[L][:,kh*hd:(kh+1)*hd]
            sc=(ks@qh)/np.sqrt(f32(hd))
            sc=np.exp(sc-sc.max()); sc/=sc.sum()
            out[h*hd:(h+1)*hd]=sc@V[L][:,kh*hd:(kh+1)*hd]
        x=x+(tens['blk.%d.attn_output.weight'%L]@out).astype(f32)
        xn=rms(x,tens['blk.%d.ffn_norm.weight'%L])
        g=(tens['blk.%d.ffn_gate.weight'%L]@xn).astype(f32)
        u=(tens['blk.%d.ffn_up.weight'%L]@xn).astype(f32)
        g=(g/(1.0+np.exp(-g))*u).astype(f32)
        x=x+(tens['blk.%d.ffn_down.weight'%L]@g).astype(f32)
    xn=rms(x,tens['output_norm.weight'])
    W=tens.get('output.weight',tens['token_embd.weight'])
    logits=(W@xn).astype(f32)

if len(sys.argv)>3 and sys.argv[3]=='greedy':
    # continue greedily N tokens
    n=int(sys.argv[4]); out=[]
    pos=len(ids)
    for _ in range(n):
        t=int(np.argmax(logits)); out.append(t)
        x=tens['token_embd.weight'][t].astype(f32)
        for L in range(n_layer):
            xn=rms(x,tens['blk.%d.attn_norm.weight'%L])
            q=(tens['blk.%d.attn_q.weight'%L]@xn).astype(f32)
            k=(tens['blk.%d.attn_k.weight'%L]@xn).astype(f32)
            v=(tens['blk.%d.attn_v.weight'%L]@xn).astype(f32)
            q=rope(q,n_head,pos); k=rope(k,n_kv,pos)
            K[L]=np.vstack([K[L],k]); V[L]=np.vstack([V[L],v])
            o=np.zeros(n_embd,dtype=f32)
            for h in range(n_head):
                kh=h//(n_head//n_kv)
                qh=q[h*hd:(h+1)*hd]
                ks=K[L][:,kh*hd:(kh+1)*hd]
                sc=(ks@qh)/np.sqrt(f32(hd))
                sc=np.exp(sc-sc.max()); sc/=sc.sum()
                o[h*hd:(h+1)*hd]=sc@V[L][:,kh*hd:(kh+1)*hd]
            x=x+(tens['blk.%d.attn_output.weight'%L]@o).astype(f32)
            xn=rms(x,tens['blk.%d.ffn_norm.weight'%L])
            g=(tens['blk.%d.ffn_gate.weight'%L]@xn).astype(f32)
            u=(tens['blk.%d.ffn_up.weight'%L]@xn).astype(f32)
            g=(g/(1.0+np.exp(-g))*u).astype(f32)
            x=x+(tens['blk.%d.ffn_down.weight'%L]@g).astype(f32)
        xn=rms(x,tens['output_norm.weight'])
        logits=(W@xn).astype(f32)
        pos+=1
    print(' '.join(map(str,out)))
else:
    for v in logits: print('%.6f'%v)
