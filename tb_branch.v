`timescale 1ns/1ps
module tb_branch;
    reg clk=0, rst_n=0;
    wire [31:0] ia, ird;
    always #5 clk = ~clk;
    memory #(.WORDS(256), .INIT("prog2.hex")) MEM (.clk(clk), .iaddr(ia), .irdata(ird));
    branch_core CPU (.clk(clk), .rst_n(rst_n), .imem_addr(ia), .imem_rdata(ird));
    initial begin
        repeat(2) @(posedge clk); rst_n = 1;
        repeat(200) @(posedge clk);
        $display("x1=%0d x2=%0d x3=%0d x5=0x%08h x6=%0d x7=%0d pc=%08h",
                 CPU.regs[1],CPU.regs[2],CPU.regs[3],CPU.regs[5],CPU.regs[6],CPU.regs[7],CPU.pc);
        $finish;
    end
endmodule
