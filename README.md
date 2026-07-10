# rv32i

An RV32I processor for the Sipeed Tang Nano 9K, written from scratch in Verilog.
Two cores live in this repo: a 3-state multicycle reference, and a 5-stage
pipeline that is diffed against it.

Both run on real hardware. The blinking LEDs and the UART output are driven by
`sw` instructions executing on the core, not by counters wired to pins.

| | CPI | Fmax | Relative throughput |
|---|---|---|---|
| `rv32i_core.v` (multicycle) | 3.0 | 47.95 MHz | 1.0× |
| `rv32i_pipe.v` (pipelined) | ~1.1 | 34.17 MHz | ~2.0× |
| `rv32i_pipe_v2.v` (pipelined) | ~1.1 | 40.24 MHz | ~2.5× |

Running at 27 MHz on the onboard oscillator.

## The design decision everything rests on

Textbook single-cycle RISC-V assumes memory answers combinationally: present an
address, data appears the same instant. FPGA block RAM does not work that way.
You present an address and the data arrives one clock edge later. Copy a
textbook single-cycle design onto real hardware and it fails.

So the reference core is a 3-state machine, one state per unit of memory
latency:

| State | On the bus | Action |
|---|---|---|
| `S_FETCH` | PC → imem | wait for BRAM |
| `S_DECODE` | instruction valid | decode; drive dmem address; stores issue here |
| `S_EXEC` | load data valid | write regfile, update PC |

Only one instruction is ever in flight, so hazards cannot exist. That property
is exactly what makes it a trustworthy reference — and it is the entire reason
it was built before the pipeline.

## Differential testing

The pipeline is never verified against intuition. It is verified against the
multicycle core.

Both cores run the same programs; `tb_diff.v` compares the register files. When
they disagree, the register that differs names the bug. Known-good answers:

- `prog2.hex` — `x3=55`, `x6=0`, `x5=0x1c` (sum 1..10 via backward branch, then a `jal` that skips one instruction)
- `prog3.hex` — `x3=ffffffff`, `x4=-1`, `x5=255`, `x9=000012ab` (sign-extension and byte enables)

The two failure modes are cleanly separated by construction: a wrong `x3` means
`imm_b` is wrong; `x6=99` means `imm_j` is wrong.

## `ex_valid`: flushing without touching the datapath

The first pipeline flushed a squashed instruction by zeroing its pipeline
registers — `ex_instr`, `ex_pc`, `ex_rs1v`, `ex_rs2v`. That is 128 bits of mux
sitting in the ID→EX path, and it cost 6 MHz.

The second version lets the datapath flow unconditionally and carries a single
`ex_valid` flip-flop instead:

```verilog
ex_instr <= id_instr;      // datapath flows unconditionally
ex_pc    <= pcd;
ex_rs1v  <= id_rs1v;
ex_rs2v  <= id_rs2v;
ex_valid <= !(ex_redirect || stall);
```

One bit replaces 128. The catch is that a squashed slot still holds real
instruction bits, so every path that *acts* on the instruction must be gated:

```verilog
wire ex_is_load  = (ex_op == OP_LOAD)  && ex_valid;
wire ex_is_store = (ex_op == OP_STORE) && ex_valid;
wire ex_reg_we   = ex_writes_rd && (ex_rd != 5'd0) && ex_valid;
```

and, critically, the branch resolver:

```verilog
if (!ex_valid) ;  // squashed slot still holds real bits: must not branch
else if (ex_op == OP_JAL) begin ex_redirect = 1'b1; ... end
```

Miss one of those gates and a dead instruction issues a phantom branch. Paths
that merely *compute* from the instruction are harmless and stay ungated.

Result: 34.17 → 40.24 MHz, with no change in IPC.

## Why Fmax went *down* from the multicycle core

Pipelining is usually sold as a clock-rate win: cut the long combinational
chain, run faster. The multicycle core's critical path is
`MEM.mem → CPU.regs → ALU carry chain → CPU.pc` — read memory, read a register,
ripple 32 bits of carry, update PC, all in one cycle. It closes at 47.95 MHz.

Cutting that chain into five stages does shorten it, but each stage boundary
adds setup and clock-to-Q overhead, and the forwarding muxes now sit directly in
front of the ALU. Net effect on this device: 40.24 MHz, about 16% *slower* than
the multicycle core.

The win is CPI, not clock. 3.0 → ~1.1 buys roughly 2.5× throughput even at the
lower clock. Worth knowing that the textbook prediction does not automatically
hold on a small FPGA.

## Hazards

- **RAW** — forwarding from EX/MEM and MEM/WB back to the EX inputs, priority to the nearer stage. Guarded with `reg_we && (rd != 0) && (rd == rs)`; dropping the `rd != 0` guard forwards a bogus `x0`.
- **Load-use** — cannot be forwarded; the data is still in memory. Detected in ID, freezes PC and IF/ID and injects a bubble for one cycle. The only unavoidable stall in RV32I.
- **Control** — branches resolve in EX; the two instructions already fetched behind a taken branch are squashed via `ex_valid`. Two cycles per taken branch.

One subtlety in IF: during a stall the instruction sitting in ID must be
re-addressed, because `imem_rdata` lags `pc` by a cycle. Freezing `pc` is not
enough.

```verilog
assign imem_addr = stall ? pcd : pc;
```

## Memory-mapped I/O

The CPU has no concept of an LED or a UART. It only knows `sw`. Address bit 31
is the entire decoder — RAM lives near `0x00000000`, so bit 31 is otherwise
always zero. One wire, no comparator.

```verilog
wire is_mmio = da[31];
wire [3:0] mem_wmask = dwm & {4{~is_mmio}};   // hide MMIO from RAM
```

| Address | Device |
|---|---|
| `0x80000000` | LEDs, low 6 bits (active low) |
| `0x80000008` | UART TX data |
| `0x8000000c` | UART busy flag (poll before writing) |

`prog6.s` prints `Hi\n` in a loop by polling the busy flag. This is how every
UART, timer, and GPIO you have ever used works.

## Files

| File | Role |
|---|---|
| `rv32i_core.v` | multicycle core — **reference, do not edit** |
| `rv32i_pipe.v` | 5-stage pipeline, v1 |
| `rv32i_pipe_v2.v` | 5-stage pipeline with `ex_valid` flush |
| `memory2.v` | unified memory: instruction read port + r/w data port, byte enables |
| `uart_tx.v` | 8N1 transmitter |
| `top.v` / `top_pipe.v` / `top_uart.v` | core + memory + MMIO + power-on reset |
| `tangnano9k.cst` | pin constraints (clk=52, led=10,11,13,14,15,16) |
| `asm.py` | minimal assembler — R, I, S, B, U, J encoders |
| `tb_diff.v` | runs both cores, diffs the register files |
| `fetch_core.v`, `alu_core.v`, `branch_core.v` | incremental checkpoints, kept for reference |

## Build

```sh
source ~/oss-cad-suite/environment

yosys -p "read_verilog top.v rv32i_core.v memory2.v; synth_gowin -top top -json cpu.json"

nextpnr-himbaechel --json cpu.json --write cpu_pnr.json \
  --device GW1NR-LV9QN88PC6/I5 \
  --vopt family=GW1N-9C --vopt cst=tangnano9k.cst

gowin_pack -d GW1N-9C -o cpu.fs cpu_pnr.json
openFPGALoader -b tangnano9k cpu.fs
```

Loads to SRAM; gone on power cycle, which is what you want while iterating. Add
`-f` to burn to flash.

Simulate:

```sh
iverilog -o sim tb_diff.v rv32i_core.v rv32i_pipe_v2.v memory2.v && ./sim
```

## Toolchain notes

Things that cost real time, recorded so they cost it only once.

- OSS CAD Suite is a GitHub release tarball, not a Homebrew cask. Clear the Gatekeeper quarantine with `./activate`.
- It is `nextpnr-himbaechel`, not `nextpnr-gowin`. Older guides say the latter and the flags differ.
- `openFPGALoader --version` errors under the suite's copy. Harmless — use `--detect`.
- Device string `GW1NR-LV9QN88PC6/I5` with `family=GW1N-9C` is confirmed correct for this board.
- LEDs are active low. Forgetting the `~` makes a working design look dead.
- `$readmemh: Not enough words` is benign when the hex file is shorter than the memory — except where a partially written word is read back. Pad `prog3.hex` to 512 words of real zeros, or `lw x9` reads `x`.
- Never build inside `~/oss-cad-suite`.

## Hardware

Sipeed Tang Nano 9K — Gowin GW1NR-9C, 27 MHz onboard oscillator on pin 52, six
active-low LEDs on pins 10, 11, 13, 14, 15, 16.

Multicycle core resource usage:

| Resource | Used | Note |
|---|---|---|
| LUT4 | 1377 / 8640 (15%) | the whole core |
| DFF | 166 / 6480 (2%) | pc, state, ir, ledreg |
| BSRAM | 8 / 26 (30%) | 512-word unified memory |
| RAM16SDP4 | 32 / 270 (11%) | register file (LUTRAM, 2 async read ports) |
