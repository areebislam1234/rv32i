`default_nettype none
module memory #(
    parameter WORDS = 256,
    parameter INIT  = "prog.hex"
)(
    input  wire        clk,
    input  wire [31:0] iaddr,
    output reg  [31:0] irdata
);
    localparam AW = $clog2(WORDS);
    reg [31:0] mem [0:WORDS-1];
    initial $readmemh(INIT, mem);
    wire [AW-1:0] ia = iaddr[AW+1:2];
    always @(posedge clk) irdata <= mem[ia];
endmodule
`default_nettype wire
