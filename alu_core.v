`default_nettype none
module alu_core (
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

    wire [6:0] opcode = instr[6:0];
    wire [4:0] rd     = instr[11:7];
    wire [2:0] funct3 = instr[14:12];
    wire [4:0] rs1    = instr[19:15];
    wire [4:0] rs2    = instr[24:20];

    localparam OP_LUI = 7'b0110111;
    localparam OP_IMM = 7'b0010011;
    localparam OP_REG = 7'b0110011;

    wire is_imm = (opcode == OP_IMM);
    wire is_reg = (opcode == OP_REG);

    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_u = {instr[31:12], 12'b0};

    reg [31:0] regs [0:31];
    integer i;
    initial for (i=0;i<32;i=i+1) regs[i]=32'b0;
    wire [31:0] rs1_val = (rs1==5'd0) ? 32'b0 : regs[rs1];
    wire [31:0] rs2_val = (rs2==5'd0) ? 32'b0 : regs[rs2];

    wire [31:0] alu_b = is_reg ? rs2_val : imm_i;
    wire [4:0]  shamt = is_reg ? rs2_val[4:0] : instr[24:20];
    wire        alt   = instr[30] & (is_reg | (is_imm & (funct3==3'b101)));

    reg [31:0] alu_out;
    always @* begin
        case (funct3)
            3'b000: alu_out = alt ? (rs1_val - alu_b) : (rs1_val + alu_b);
            3'b001: alu_out = rs1_val << shamt;
            3'b010: alu_out = {31'b0, ($signed(rs1_val) < $signed(alu_b))};
            3'b011: alu_out = {31'b0, (rs1_val < alu_b)};
            3'b100: alu_out = rs1_val ^ alu_b;
            3'b101: alu_out = alt ? ($signed(rs1_val) >>> shamt) : (rs1_val >> shamt);
            3'b110: alu_out = rs1_val | alu_b;
            3'b111: alu_out = rs1_val & alu_b;
        endcase
    end

    wire [31:0] wb = (opcode==OP_LUI) ? imm_u : alu_out;
    wire writes_rd = (opcode==OP_LUI)||(opcode==OP_IMM)||(opcode==OP_REG);
    wire reg_we = writes_rd && (rd != 5'd0);

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= S_FETCH; pc <= 32'h0; ir <= 32'h00000013;
        end else case (state)
            S_FETCH:  state <= S_DECODE;
            S_DECODE: begin ir <= imem_rdata; state <= S_EXEC; end
            S_EXEC: begin
                if (reg_we) regs[rd] <= wb;
                pc <= pc + 32'd4;
                state <= S_FETCH;
            end
            default: state <= S_FETCH;
        endcase
    end
endmodule
`default_nettype wire
