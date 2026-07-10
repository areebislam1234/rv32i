module top (
    input  wire       clk,
    output wire [5:0] led
);
    reg [24:0] cnt = 0;
    always @(posedge clk) cnt <= cnt + 1;
    assign led = ~{6{cnt[24]}};
endmodule
