`default_nettype none
// 8N1: idle high, start bit (0), 8 data bits LSB-first, stop bit (1).
module uart_tx #(
    parameter CLK_HZ = 27_000_000,
    parameter BAUD   = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,      // pulse one cycle to send
    input  wire [7:0] data,
    output wire       tx,
    output wire       busy
);
    localparam integer DIV = CLK_HZ / BAUD;   // 27e6/115200 = 234 (0.16% fast)

    reg [15:0] cnt;
    reg [3:0]  bitcnt;
    reg [9:0]  sh;
    reg        active;

    assign busy = active;
    assign tx   = active ? sh[0] : 1'b1;

    always @(posedge clk) begin
        if (!rst_n) begin
            active <= 1'b0; cnt <= 16'd0; bitcnt <= 4'd0; sh <= 10'h3ff;
        end else if (!active) begin
            if (start) begin
                sh     <= {1'b1, data, 1'b0};
                active <= 1'b1;
                cnt    <= 16'd0;
                bitcnt <= 4'd0;
            end
        end else begin
            if (cnt == DIV-1) begin
                cnt <= 16'd0;
                sh  <= {1'b1, sh[9:1]};
                if (bitcnt == 4'd9) active <= 1'b0;
                bitcnt <= bitcnt + 4'd1;
            end else begin
                cnt <= cnt + 16'd1;
            end
        end
    end
endmodule
`default_nettype wire
