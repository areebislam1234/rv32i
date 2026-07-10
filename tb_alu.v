`timescale 1ns/1ps
module tb_alu;
    reg clk=0, rst_n=0;
    wire [31:0] ia, ird;
    integer k;
    always #5 clk = ~clk;
    memory #(.WORDS(256), .INIT("prog.hex")) MEM (.clk(clk), .iaddr(ia), .irdata(ird));
    alu_core CPU (.clk(clk), .rst_n(rst_n), .imem_addr(ia), .imem_rdata(ird));
    initial begin
        repeat(2) @(posedge clk); rst_n = 1;
        repeat(11*3+2) @(posedge clk);
        for (k=1;k<=11;k=k+1) $display("x%0d = %0d (0x%08h)", k, CPU.regs[k], CPU.regs[k]);
        $finish;
    end
endmodule
