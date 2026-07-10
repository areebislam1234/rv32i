`default_nettype none
module fetch_core (
    input  wire        clk,
    input  wire        rst_n,
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata
);
    localparam S_FETCH=2'd0, S_DECODE=2'd1, S_EXEC=2'd2;
    reg [1:0]  state;
    reg [31:0] pc, ir;
    wire [31:0] instr = (state == S_DECODE) ? imem_rdata : ir;
    assign imem_addr = pc;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= S_FETCH; pc <= 32'h0; ir <= 32'h00000013;
        end else case (state)
            S_FETCH:  state <= S_DECODE;
            S_DECODE: begin ir <= imem_rdata; state <= S_EXEC; end
            S_EXEC:   begin pc <= pc + 32'd4; state <= S_FETCH; end
            default:  state <= S_FETCH;
        endcase
    end
endmodule
`default_nettype wire
