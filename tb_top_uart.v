`timescale 1ns/1ps
module tb_top_uart;
    reg clk=0; always #5 clk=~clk;
    wire [5:0] led; wire tx;
    integer k, n; reg [7:0] b;
    localparam DIV = 16;
    top #(.CLK_HZ(1600), .BAUD(100), .INIT("prog6sim.hex")) DUT
        (.clk(clk), .led(led), .uart_tx_pin(tx));
    initial begin
        for (n=0; n<9; n=n+1) begin
            @(negedge tx);
            repeat(DIV + DIV/2) @(posedge clk);
            for (k=0;k<8;k=k+1) begin
                b[k] = tx;
                repeat(DIV) @(posedge clk);
            end
            if (b == 8'h0a) $display("rx: 0a  (newline)");
            else            $display("rx: %02h  '%s'", b, b);
        end
        $display("tb_top_uart: done");
        $finish;
    end
    initial begin #4000000; $display("TIMEOUT - nothing transmitted"); $finish; end
endmodule
