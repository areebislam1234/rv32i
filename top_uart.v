`default_nettype none
// Bit 31 set = MMIO, never RAM. Bits [3:2] pick the register.
//   0x80000000  W   low 6 bits -> LEDs
//   0x80000008  W   low 8 bits -> UART transmit
//   0x8000000C  R   bit 0 = UART busy
module top #(
    parameter CLK_HZ = 27_000_000,
    parameter BAUD   = 115200,
    parameter INIT   = "prog6.hex"
)(
    input  wire       clk,
    output wire [5:0] led,
    output wire       uart_tx_pin
);
    reg [7:0] rstcnt = 8'd0;
    wire rst_n = rstcnt[7];
    always @(posedge clk) if (!rst_n) rstcnt <= rstcnt + 8'd1;

    wire [31:0] ia, ird, da, dwd, drd;
    wire [3:0]  dwm;

    wire is_mmio = da[31];
    wire [1:0] sel = da[3:2];
    wire [3:0] mem_wmask = dwm & {4{~is_mmio}};

    memory2 #(.WORDS(512), .INIT(INIT)) MEM (
        .clk(clk), .iaddr(ia), .irdata(ird),
        .daddr(da), .dwdata(dwd), .dwmask(mem_wmask), .drdata(drd));

    // drdata is registered inside memory2, so load data reaches the CPU one
    // cycle after the address goes out. Delay the MMIO mux to match.
    reg        is_mmio_d;
    reg [31:0] mmio_rd;
    wire       uart_busy;
    always @(posedge clk) begin
        is_mmio_d <= is_mmio;
        mmio_rd   <= (sel == 2'b11) ? {31'b0, uart_busy} : 32'b0;
    end
    wire [31:0] cpu_drd = is_mmio_d ? mmio_rd : drd;

    rv32i_pipe CPU (
        .clk(clk), .rst_n(rst_n), .imem_addr(ia), .imem_rdata(ird),
        .dmem_addr(da), .dmem_wdata(dwd), .dmem_wmask(dwm), .dmem_rdata(cpu_drd));

    reg [5:0] ledreg = 6'b0;
    always @(posedge clk) if (is_mmio && sel == 2'b00 && |dwm) ledreg <= dwd[5:0];
    assign led = ~ledreg;

    // A store asserts dwm for exactly one cycle: a clean start pulse.
    wire uart_start = is_mmio && (sel == 2'b10) && |dwm;

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) UART (
        .clk(clk), .rst_n(rst_n),
        .start(uart_start), .data(dwd[7:0]),
        .tx(uart_tx_pin), .busy(uart_busy));
endmodule
`default_nettype wire
