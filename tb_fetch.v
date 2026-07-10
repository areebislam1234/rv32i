`timescale 1ns/1ps
module tb_fetch;
    reg clk=0, rst_n=0;
    wire [31:0] ia, ird;
    always #5 clk = ~clk;
    memory #(.WORDS(256), .INIT("prog.hex")) MEM (.clk(clk), .iaddr(ia), .irdata(ird));
    fetch_core CPU (.clk(clk), .rst_n(rst_n), .imem_addr(ia), .imem_rdata(ird));
    initial begin
        repeat(2) @(posedge clk); rst_n = 1;
        repeat(15) begin
            @(posedge clk);
            $display("t=%0t state=%0d pc=%08h ir=%08h", $time, CPU.state, CPU.pc, CPU.ir);
        end
        $finish;
    end
endmodule
