#!/usr/bin/env python3
"""asm.py in.s out.hex [words]   -- minimal RV32I assembler, pads with zeros."""
import sys, re

R = {'add':(0x33,0,0x00),'sub':(0x33,0,0x20),'sll':(0x33,1,0),'slt':(0x33,2,0),
     'sltu':(0x33,3,0),'xor':(0x33,4,0),'srl':(0x33,5,0x00),'sra':(0x33,5,0x20),
     'or':(0x33,6,0),'and':(0x33,7,0)}
I = {'addi':(0x13,0),'slti':(0x13,2),'sltiu':(0x13,3),'xori':(0x13,4),
     'ori':(0x13,6),'andi':(0x13,7),'jalr':(0x67,0)}
SH= {'slli':(0x13,1,0x00),'srli':(0x13,5,0x00),'srai':(0x13,5,0x20)}
L = {'lb':0,'lh':1,'lw':2,'lbu':4,'lhu':5}
S = {'sb':0,'sh':1,'sw':2}
B = {'beq':0,'bne':1,'blt':4,'bge':5,'bltu':6,'bgeu':7}
U = {'lui':0x37,'auipc':0x17}

def reg(t):
    t = t.strip()
    if t.startswith('x'): return int(t[1:])
    raise ValueError('bad register %r' % t)

def imm(t, labels=None, pc=None, rel=False):
    t = t.strip()
    if labels and t in labels:
        return labels[t] - pc if rel else labels[t]
    return int(t, 0)

def parse_mem(t):
    m = re.match(r'(-?\w+)\((x\d+)\)$', t.strip())
    return int(m.group(1), 0), reg(m.group(2))

def assemble(src):
    lines, labels, pc = [], {}, 0
    for raw in src.splitlines():
        line = raw.split('#')[0].strip()
        if not line: continue
        while ':' in line:
            lab, line = line.split(':', 1)
            labels[lab.strip()] = pc
            line = line.strip()
        if line:
            lines.append((pc, line)); pc += 4

    out = []
    for pc, line in lines:
        op, _, rest = line.partition(' ')
        a = [x.strip() for x in rest.split(',')] if rest.strip() else []
        if op in R:
            o, f3, f7 = R[op]
            w = (f7 << 25) | (reg(a[2]) << 20) | (reg(a[1]) << 15) | (f3 << 12) | (reg(a[0]) << 7) | o
        elif op in SH:
            o, f3, f7 = SH[op]
            w = (f7 << 25) | ((imm(a[2]) & 31) << 20) | (reg(a[1]) << 15) | (f3 << 12) | (reg(a[0]) << 7) | o
        elif op in I:
            o, f3 = I[op]
            if op == 'jalr' and '(' in a[1]:
                im, rs1 = parse_mem(a[1])
            else:
                rs1, im = reg(a[1]), imm(a[2])
            w = ((im & 0xfff) << 20) | (rs1 << 15) | (f3 << 12) | (reg(a[0]) << 7) | o
        elif op in L:
            im, rs1 = parse_mem(a[1])
            w = ((im & 0xfff) << 20) | (rs1 << 15) | (L[op] << 12) | (reg(a[0]) << 7) | 0x03
        elif op in S:
            im, rs1 = parse_mem(a[1])
            w = (((im >> 5) & 0x7f) << 25) | (reg(a[0]) << 20) | (rs1 << 15) | \
                (S[op] << 12) | ((im & 0x1f) << 7) | 0x23
        elif op in B:
            d = imm(a[2], labels, pc, rel=True)
            w = (((d >> 12) & 1) << 31) | (((d >> 5) & 0x3f) << 25) | (reg(a[1]) << 20) | \
                (reg(a[0]) << 15) | (B[op] << 12) | (((d >> 1) & 0xf) << 8) | \
                (((d >> 11) & 1) << 7) | 0x63
        elif op in U:
            w = ((imm(a[1]) & 0xfffff) << 12) | (reg(a[0]) << 7) | U[op]
        elif op == 'jal':
            d = imm(a[1], labels, pc, rel=True)
            w = (((d >> 20) & 1) << 31) | (((d >> 1) & 0x3ff) << 21) | (((d >> 11) & 1) << 20) | \
                (((d >> 12) & 0xff) << 12) | (reg(a[0]) << 7) | 0x6f
        elif op == 'nop':
            w = 0x13
        else:
            raise ValueError('unknown opcode %r in: %s' % (op, line))
        out.append(w & 0xffffffff)
    return out

if __name__ == '__main__':
    words = assemble(open(sys.argv[1]).read())
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 512
    with open(sys.argv[2], 'w') as f:
        for w in words: f.write('%08x\n' % w)
        for _ in range(n - len(words)): f.write('00000000\n')
    print('%s: %d instructions, padded to %d words' % (sys.argv[2], len(words), n))
