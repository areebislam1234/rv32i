`timescale 1ns/1ps
`ifndef PROG
 `define PROG "prog2.hex"
`endif
`ifndef CYC
 `define CYC 400
`endif
module tb_diff;
    reg clk=0, rst_n=0;
    integer k, bad;
    always #5 clk = ~clk;

    wire [31:0] a_ia,a_ird,a_da,a_dwd,a_drd; wire [3:0] a_dwm;
    memory2 #(.WORDS(512), .INIT(`PROG)) AMEM (.clk(clk),.iaddr(a_ia),.irdata(a_ird),
        .daddr(a_da),.dwdata(a_dwd),.dwmask(a_dwm),.drdata(a_drd));
    rv32i_core ACPU (.clk(clk),.rst_n(rst_n),.imem_addr(a_ia),.imem_rdata(a_ird),
        .dmem_addr(a_da),.dmem_wdata(a_dwd),.dmem_wmask(a_dwm),.dmem_rdata(a_drd));

    wire [31:0] b_ia,b_ird,b_da,b_dwd,b_drd; wire [3:0] b_dwm;
    memory2 #(.WORDS(512), .INIT(`PROG)) BMEM (.clk(clk),.iaddr(b_ia),.irdata(b_ird),
        .daddr(b_da),.dwdata(b_dwd),.dwmask(b_dwm),.drdata(b_drd));
    rv32i_pipe BCPU (.clk(clk),.rst_n(rst_n),.imem_addr(b_ia),.imem_rdata(b_ird),
        .dmem_addr(b_da),.dmem_wdata(b_dwd),.dmem_wmask(b_dwm),.dmem_rdata(b_drd));

    initial begin
        repeat(2) @(posedge clk); rst_n = 1;
        repeat(`CYC) @(posedge clk);
        bad = 0;
        for (k=1;k<32;k=k+1)
            if (ACPU.regs[k] !== BCPU.regs[k]) begin
                bad = bad + 1;
                $display("MISMATCH x%0d: ref=%08h pipe=%08h", k, ACPU.regs[k], BCPU.regs[k]);
            end
        if (bad==0) $display("PASS  %s : all 31 registers match", `PROG);
        else        $display("FAIL  %s : %0d register(s) differ", `PROG, bad);
        $finish;
    end
endmodule
