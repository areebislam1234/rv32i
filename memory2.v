`default_nettype none
module memory2 #(
    parameter WORDS = 512,
    parameter INIT  = "prog3.hex"
)(
    input  wire        clk,
    input  wire [31:0] iaddr,
    output reg  [31:0] irdata,
    input  wire [31:0] daddr,
    input  wire [31:0] dwdata,
    input  wire [3:0]  dwmask,
    output reg  [31:0] drdata
);
    localparam AW = $clog2(WORDS);
    reg [31:0] mem [0:WORDS-1];
    initial $readmemh(INIT, mem);
    wire [AW-1:0] ia = iaddr[AW+1:2];
    wire [AW-1:0] da = daddr[AW+1:2];
    always @(posedge clk) begin
        irdata <= mem[ia];
        drdata <= mem[da];
        if (dwmask[0]) mem[da][ 7: 0] <= dwdata[ 7: 0];
        if (dwmask[1]) mem[da][15: 8] <= dwdata[15: 8];
        if (dwmask[2]) mem[da][23:16] <= dwdata[23:16];
        if (dwmask[3]) mem[da][31:24] <= dwdata[31:24];
    end
endmodule
`default_nettype wire
