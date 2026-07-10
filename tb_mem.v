`timescale 1ns/1ps
module tb_mem;
    reg clk=0, rst_n=0;
    wire [31:0] ia, ird, da, dwd, drd; wire [3:0] dwm;
    always #5 clk = ~clk;
    memory2 #(.WORDS(512), .INIT("prog3.hex")) MEM (.clk(clk), .iaddr(ia), .irdata(ird),
        .daddr(da), .dwdata(dwd), .dwmask(dwm), .drdata(drd));
    rv32i_core CPU (.clk(clk), .rst_n(rst_n), .imem_addr(ia), .imem_rdata(ird),
        .dmem_addr(da), .dmem_wdata(dwd), .dmem_wmask(dwm), .dmem_rdata(drd));
    initial begin
        repeat(2) @(posedge clk); rst_n = 1;
        repeat(60) @(posedge clk);
        $display("x3=%08h x4=%0d x5=%0d x6=%0d x9=%08h x10=%0d",
          CPU.regs[3],$signed(CPU.regs[4]),CPU.regs[5],CPU.regs[6],CPU.regs[9],CPU.regs[10]);
        $finish;
    end
endmodule
