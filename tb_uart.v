`timescale 1ns/1ps
module tb_uart;
    reg clk=0, rst_n=0, start=0; reg [7:0] data;
    wire tx, busy;
    integer k; reg [7:0] got;
    localparam DIV = 16;
    always #5 clk = ~clk;
    uart_tx #(.CLK_HZ(16), .BAUD(1)) U (.clk(clk),.rst_n(rst_n),.start(start),
                                        .data(data),.tx(tx),.busy(busy));
    task send_and_check(input [7:0] b);
    begin
        wait (!busy);
        @(posedge clk); data = b; start = 1;
        @(posedge clk); start = 0;
        repeat(DIV/2 - 1) @(posedge clk);
        if (tx !== 1'b0) $display("  BAD start bit for %02h", b);
        for (k=0;k<8;k=k+1) begin
            repeat(DIV) @(posedge clk);
            got[k] = tx;
        end
        repeat(DIV) @(posedge clk);
        if (tx !== 1'b1) $display("  BAD stop bit for %02h", b);
        if (got === b) $display("  ok  sent %02h  received %02h", b, got);
        else           $display("  FAIL sent %02h  received %02h", b, got);
    end
    endtask
    initial begin
        repeat(2) @(posedge clk); rst_n = 1;
        if (busy !== 1'b0) $display("  BAD: busy high at idle");
        if (tx   !== 1'b1) $display("  BAD: tx not idle-high");
        send_and_check(8'h48);
        send_and_check(8'h69);
        send_and_check(8'h0a);
        send_and_check(8'h00);
        send_and_check(8'hff);
        $display("uart_tx: done");
        $finish;
    end
endmodule
