# rv32i

An RV32I processor for the Sipeed Tang Nano 9K, written from scratch in Verilog.
Two cores live here: a 3-state multicycle reference, and a 5-stage pipeline that
is diffed against it.

Both run on real hardware at 27 MHz. The LEDs and the UART output are driven by
`sw` instructions executing on the core, not by counters wired to pins.

## Results

Measured on `prog2.hex` (sum 1..10 via a backward branch, then a jump) with
`tb_cycles.v`. 35 instructions retired.

| | cycles | CPI |
|---|---|---|
| `rv32i_core.v` (multicycle) | 106 | 3.00 |
| `rv32i_pipe.v` (pipeline v1) | 60 | 1.70 |
| `rv32i_pipe_v2.v` (pipeline v2) | 60 | 1.70 |

All three produce `x3=55`, `x6=0`, `x5=0x1c`. v1 and v2 are cycle-identical, so
`ex_valid` (below) changed timing and nothing else.

Pipelining cut CPI by 1.76×. It did **not** obviously raise the clock — see the
Fmax section. Throughput is `frequency / CPI` and only one of those terms is
pinned down here.

**CPI is a property of the program, not the CPU.** `prog2` is a three-instruction
loop that takes a branch on every pass. Branches resolve in EX and cost a 2-cycle
flush, so roughly a third of retired instructions pay a penalty. That is close to
worst case. Quoting a CPI without naming the program says nothing.

## The design decision everything rests on

Textbook single-cycle RISC-V assumes memory answers combinationally: present an
address, data appears the same instant. FPGA block RAM does not work that way.
Present an address and the data arrives one clock edge later. Copy a textbook
single-cycle design onto real hardware and it fails.

So the reference core is a 3-state machine, one state per unit of memory latency:

| State | On the bus | Action |
|---|---|---|
| `S_FETCH` | PC → imem | wait for BRAM |
| `S_DECODE` | instruction valid | decode; drive dmem address; stores issue here |
| `S_EXEC` | load data valid | write regfile, update PC |

Exactly 3 cycles per instruction, always. Only one instruction is ever in flight,
so hazards cannot exist. That property is what makes it a trustworthy reference,
and it is the entire reason it was built before the pipeline.

It also makes the CPI measurement free: the multicycle core is a calibrated
instrument. `instructions = mc_cycles / 3`, so
`pipeline_CPI = 3 × pipe_cycles / mc_cycles`, with no instruction counting.

## Differential testing

The pipeline is never verified against intuition. It is verified against the
multicycle core.

Both cores run the same program; `tb_diff.v` compares the register files. When
they disagree, the register that differs names the bug.

| test | v1 | v2 |
|---|---|---|
| `prog2.hex` — branches, jumps | PASS (31/31) | PASS (31/31) |
| `prog3.hex` — loads, stores, byte enables | not run | PASS (31/31) |

Known-good answers: `prog2` → `x3=55`, `x6=0`, `x5=0x1c`. `prog3` →
`x3=ffffffff`, `x4=-1`, `x5=255`, `x9=000012ab`. The failure modes are separated
by construction: a wrong `x3` means `imm_b` is wrong; `x6=99` means `imm_j` is
wrong.

**Correctness is not enough on its own.** `prog2` passes all 31 register checks
even if the branch flush is completely broken, because the instructions squashed
behind each taken branch happen to be harmless here. Only the cycle count catches
that: a pipeline that never flushes retires `prog2` in 39 cycles with `x3=55`.
Measuring 60 is what proves the flush is real. `tb_diff` checks architectural
state; `tb_cycles` checks the microarchitecture. Neither alone is sufficient.

## `ex_valid`: flushing without touching the datapath

v1 flushed a squashed instruction by zeroing its pipeline registers —
`ex_instr`, `ex_pc`, `ex_rs1v`, `ex_rs2v`. That is 128 bits of mux sitting in the
ID→EX path.

v2 lets the datapath flow unconditionally and carries a single `ex_valid`
flip-flop instead:

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

Verified cycle-identical to v1 on `prog2` (60 cycles both). Whether it is
measurably faster in MHz is **not established** — see below.

## Fmax: why there is no number here

An earlier version of this README reported 47.95 MHz for the multicycle core,
34.17 for pipeline v1, and 40.24 for v2, and derived a 1.48× speedup from them.
Those numbers are withdrawn.

Two identical `nextpnr` runs on identical source, back to back, with no
constraint given:

```
Info: Max frequency for clock 'CPU.clk': 68.07 MHz (PASS at 12.00 MHz)
Info: Max frequency for clock 'CPU.clk': 47.95 MHz (PASS at 12.00 MHz)
```

Same design. 42% spread. `nextpnr`'s placer is a seeded annealer, and reported
Fmax is a static-timing estimate over whatever placement it happened to land on,
not a property of the design. A single unseeded run produces a number with two
decimal places and no meaning.

The claimed `34.17 → 40.24` improvement from `ex_valid` is a 6 MHz difference
measured against a tool whose run-to-run noise here was 20 MHz. It is inside the
noise floor. It may be real. One sample of each cannot tell.

Settling it properly means several seeds per design at the real target frequency,
comparing medians against the spread:

```sh
for s in 1 2 3 4 5; do
  nextpnr-himbaechel --json cpu.json --write /dev/null \
    --device GW1NR-LV9QN88PC6/I5 --vopt family=GW1N-9C \
    --vopt cst=tangnano9k.cst --freq 27 --seed $s 2>&1 | grep -i 'max frequency'
done
```

Not done yet. Until it is, the only defensible frequency claim about this project
is the observed one: **everything runs correctly on hardware at 27 MHz.**

The architectural argument for `ex_valid` — a 1-bit flush is smaller than a
128-bit one — stands on its own and does not need a timing number.

## Hazards

- **RAW** — forwarding from EX/MEM and MEM/WB back to the EX inputs, priority to the nearer stage. Guarded with `reg_we && (rd != 0) && (rd == rs)`; dropping the `rd != 0` guard forwards a bogus `x0`.
- **Load-use** — cannot be forwarded; the data is still in memory. Detected in ID, freezes PC and IF/ID, injects a bubble for one cycle. The only unavoidable stall in RV32I.
- **Control** — branches resolve in EX; the two instructions already fetched behind a taken branch are squashed via `ex_valid`. 2 cycles per redirect.

Control hazards dominate. At CPI 1.70 on `prog2`, flushes account for ~35% of all
cycles. Resolving branches in ID would halve the penalty to 1 cycle (CPI ≈ 1.4)
at the cost of a comparator on the ID critical path. Whether that nets out is an
empirical question — and answering it requires the multi-seed Fmax methodology
above, not a single run.

One subtlety in IF: during a stall, the instruction sitting in ID must be
re-addressed, because `imem_rdata` lags `pc` by a cycle. Freezing `pc` is not
enough.

```verilog
assign imem_addr = stall ? pcd : pc;
```

Another, in the testbench: a parked pipeline does not have a stationary PC. Even
sitting in `jal x0,0` it keeps speculatively fetching ahead and redirecting back,
forever. Halt detection must watch a committed architectural result, not the PC.

## Memory-mapped I/O

The CPU has no concept of an LED or a UART. It only knows `sw`. Address bit 31 is
the entire decoder — RAM lives near `0x00000000`, so bit 31 is otherwise always
zero. One wire, no comparator.

```verilog
wire is_mmio = da[31];
wire [3:0] mem_wmask = dwm & {4{~is_mmio}};   // hide MMIO from RAM
```

| Address | Device |
|---|---|
| `0x80000000` | LEDs, low 6 bits (active low) |
| `0x80000008` | UART TX data |
| `0x8000000c` | UART busy flag (poll before writing) |

(The UART addresses are read off `prog6.s`, not confirmed against `top_uart.v`.)

`prog6.s` prints `Hi\n` in a loop by polling the busy flag. This is how every
UART, timer, and GPIO you have ever used works.

## Files

| File | Role |
|---|---|
| `rv32i_core.v` | multicycle core — **reference, do not edit** |
| `rv32i_pipe.v` | pipeline v1, `module rv32i_pipe_v1` (kept so the `ex_valid` diff is readable) |
| `rv32i_pipe_v2.v` | pipeline v2, `module rv32i_pipe` |
| `memory2.v` | unified memory: instruction read port + r/w data port, byte enables |
| `uart_tx.v` | 8N1 transmitter |
| `top.v` / `top_pipe.v` / `top_uart.v` | core + memory + MMIO + power-on reset |
| `tangnano9k.cst` | pin constraints (clk=52, led=10,11,13,14,15,16) |
| `asm.py` | minimal assembler — R, I, S, B, U, J encoders |
| `tb_diff.v` | runs both cores, diffs the register files |
| `tb_cycles.v` | counts cycles to retirement; the CPI instrument |
| `fetch_core.v`, `alu_core.v`, `branch_core.v` | incremental checkpoints, kept for reference |

`top_pipe.v` instantiates `rv32i_pipe`, which now unambiguously means v2. To
synthesize v1 you need a top that instantiates `rv32i_pipe_v1`.

## Build

```sh
source ~/oss-cad-suite/environment

yosys -p "read_verilog top.v rv32i_core.v memory2.v; synth_gowin -top top -json cpu.json"

nextpnr-himbaechel --json cpu.json --write cpu_pnr.json \
  --device GW1NR-LV9QN88PC6/I5 \
  --vopt family=GW1N-9C --vopt cst=tangnano9k.cst \
  --freq 27 --seed 1

gowin_pack -d GW1N-9C -o cpu.fs cpu_pnr.json
openFPGALoader -b tangnano9k cpu.fs
```

Pass `--freq` and `--seed` explicitly. Without them the placer targets 12 MHz and
picks a random seed, and the Fmax it reports is not reproducible.

Loads to SRAM; gone on power cycle, which is what you want while iterating. Add
`-f` to burn to flash. Only the last command needs the board attached.

Simulate and measure:

```sh
# correctness: pipeline vs reference
iverilog -o d2 -DPROG=\"prog2.hex\" tb_diff.v rv32i_core.v rv32i_pipe_v2.v memory2.v && ./d2
iverilog -o d3 -DPROG=\"prog3.hex\" tb_diff.v rv32i_core.v rv32i_pipe_v2.v memory2.v && ./d3

# cycles: the CPI instrument
iverilog -o cyc_mc -DCORE=rv32i_core    -DHEX=\"prog2.hex\" tb_cycles.v rv32i_core.v    memory2.v && ./cyc_mc
iverilog -o cyc_p1 -DCORE=rv32i_pipe_v1 -DHEX=\"prog2.hex\" tb_cycles.v rv32i_pipe.v    memory2.v && ./cyc_p1
iverilog -o cyc_p2 -DCORE=rv32i_pipe    -DHEX=\"prog2.hex\" tb_cycles.v rv32i_pipe_v2.v memory2.v && ./cyc_p2
```

## Toolchain notes

Things that cost real time, recorded so they cost it only once.

- OSS CAD Suite is a GitHub release tarball, not a Homebrew cask. Clear the Gatekeeper quarantine with `./activate`.
- `source ~/oss-cad-suite/environment` in every new terminal. Not in `.zshrc` — it shadows the system Python.
- It is `nextpnr-himbaechel`, not `nextpnr-gowin`. Older guides say the latter and the flags differ.
- `openFPGALoader --version` errors under the suite's copy. Harmless — use `--detect`.
- Device string `GW1NR-LV9QN88PC6/I5` with `family=GW1N-9C` is confirmed correct for this board.
- LEDs are active low. Forgetting the `~` makes a working design look dead.
- `$readmemh: Not enough words` is benign when the hex file is shorter than the memory — except where a partially written word is read back. Pad `prog3.hex` to 512 words of real zeros, or `lw x9` reads `x`.
- Never build inside `~/oss-cad-suite`.
- Two `.v` files declaring the same module name do not error. `iverilog` and `yosys` silently use whichever file was passed. Keep module names unique.
- zsh does not treat `#` as a comment interactively, and aborts a command when a glob matches nothing.

## Hardware

Sipeed Tang Nano 9K — Gowin GW1NR-9C, 27 MHz onboard oscillator on pin 52, six
active-low LEDs on pins 10, 11, 13, 14, 15, 16. Host: macOS, Apple Silicon.

Multicycle core resource usage (single unseeded run, so treat as approximate):

| Resource | Used |
|---|---|
| LUT4 | 1377 / 8640 (15%) |
| DFF | 166 / 6480 (2%) |
| BSRAM | 8 / 26 (30%) |
| RAM16SDP4 | 32 / 270 (11%) |

## License

MIT.
