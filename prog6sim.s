    lui  x1, 0x80000        # MMIO base
    addi x2, x0, 72         # 'H'
    addi x3, x0, 105        # 'i'
    addi x4, x0, 10         # newline
loop:
w1: lw   x5, 12(x1)         # poll busy
    bne  x5, x0, w1
    sw   x2, 8(x1)
w2: lw   x5, 12(x1)
    bne  x5, x0, w2
    sw   x3, 8(x1)
w3: lw   x5, 12(x1)
    bne  x5, x0, w3
    sw   x4, 8(x1)
    addi x6, x0, 3           # delay so output is readable
d:  addi x6, x6, -1
    bne  x6, x0, d
    jal  x0, loop
