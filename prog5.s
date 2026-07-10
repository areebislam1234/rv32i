    addi x1, x0, 256
    addi x2, x0, 42
    sw   x2, 0(x1)
    addi x3, x0, 7
    sw   x3, 4(x1)

    lw   x4, 0(x1)
    add  x5, x4, x4

    lw   x6, 4(x1)
    sw   x6, 8(x1)
    lw   x7, 8(x1)

    lw   x8, 0(x1)
    nop
    add  x9, x8, x0

    addi x10, x0, 1
    addi x11, x10, 1
    addi x12, x11, 1
    add  x13, x10, x11

    addi x14, x0, 5
    nop
    nop
    add  x15, x14, x14

    addi x0, x0, 99
    add  x16, x0, x0
park:
    jal  x0, park
