`default_nettype none
module top (
    input  wire       clk,
    output wire [5:0] led
);
    reg [7:0] rstcnt = 8'd0;
    wire rst_n = rstcnt[7];
    always @(posedge clk) if (!rst_n) rstcnt <= rstcnt + 8'd1;

    wire [31:0] ia, ird, da, dwd, drd;
    wire [3:0]  dwm;
    wire is_mmio = da[31];
    wire [3:0] mem_wmask = dwm & {4{~is_mmio}};

    memory2 #(.WORDS(512), .INIT("prog4.hex")) MEM (
        .clk(clk), .iaddr(ia), .irdata(ird),
        .daddr(da), .dwdata(dwd), .dwmask(mem_wmask), .drdata(drd));

    rv32i_pipe CPU (
        .clk(clk), .rst_n(rst_n), .imem_addr(ia), .imem_rdata(ird),
        .dmem_addr(da), .dmem_wdata(dwd), .dmem_wmask(dwm), .dmem_rdata(drd));

    reg [5:0] ledreg = 6'b0;
    always @(posedge clk) if (is_mmio && |dwm) ledreg <= dwd[5:0];
    assign led = ~ledreg;
endmodule
`default_nettype wire
