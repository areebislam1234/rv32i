`default_nettype none
`timescale 1ns/1ps

// Counts clock cycles until prog2's final instruction (addi x7,x0,42) retires.
//
//   iverilog -o cyc_mc -DCORE=rv32i_core -DHEX=\"prog2.hex\" tb_cycles.v rv32i_core.v    memory2.v && ./cyc_mc
//   iverilog -o cyc_p2 -DCORE=rv32i_pipe -DHEX=\"prog2.hex\" tb_cycles.v rv32i_pipe_v2.v memory2.v && ./cyc_p2
//
// Halting on "PC stopped moving" does not work for a pipeline: parked in
// jal x0,0 the PC keeps speculatively fetching ahead and getting redirected
// back, forever. Watch a committed architectural result instead.
//
//     instructions = mc_cycles / 3        (multicycle is exactly 3 CPI)
//     pipeline CPI = 3 * pipe_cycles / mc_cycles

`ifndef CORE
`define CORE rv32i_core
`endif
`ifndef HEX
`define HEX "prog2.hex"
`endif

module tb_cycles;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    wire [31:0] ia, ird, da, dwd, drd;
    wire [3:0]  dwm;

    memory2 #(.WORDS(512), .INIT(`HEX)) MEM (
        .clk(clk), .iaddr(ia), .irdata(ird),
        .daddr(da), .dwdata(dwd), .dwmask(dwm), .drdata(drd));

    `CORE uut (
        .clk(clk), .rst_n(rst_n),
        .imem_addr(ia), .imem_rdata(ird),
        .dmem_addr(da), .dmem_wdata(dwd), .dmem_wmask(dwm), .dmem_rdata(drd));

    reg [31:0] cycles = 0;

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1;
    end

    always @(posedge clk) if (rst_n) begin
        cycles <= cycles + 1;

        if (uut.regs[7] == 32'd42) begin
            $display("program = %s", `HEX);
            $display("cycles  = %0d", cycles);
            $display("x3      = %0d  (expect 55)", uut.regs[3]);
            $display("x6      = %0d  (expect 0)",  uut.regs[6]);
            $display("x5      = 0x%08x  (expect 0x1c)", uut.regs[5]);
            $finish;
        end
    end

    initial begin
        #200000;
        $display("TIMEOUT - x7 never reached 42");
        $finish;
    end
endmodule
`default_nettype wire
