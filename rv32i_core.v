`default_nettype none
module rv32i_core (
    input  wire        clk,
    input  wire        rst_n,
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire [3:0]  dmem_wmask,
    input  wire [31:0] dmem_rdata
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

    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_IMM    = 7'b0010011;
    localparam OP_REG    = 7'b0110011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;

    wire is_imm   = (opcode == OP_IMM);
    wire is_reg   = (opcode == OP_REG);
    wire is_store = (opcode == OP_STORE);

    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};

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

    wire [31:0] mem_addr = rs1_val + (is_store ? imm_s : imm_i);
    wire [1:0]  boff = mem_addr[1:0];
    assign dmem_addr = mem_addr;

    reg [3:0] wmask; reg [31:0] wdata;
    always @* begin
        case (funct3)
            3'b000: begin wmask = 4'b0001 << boff;           wdata = rs2_val << (8*boff); end
            3'b001: begin wmask = 4'b0011 << {boff[1],1'b0}; wdata = rs2_val << (16*boff[1]); end
            default:begin wmask = 4'b1111;                   wdata = rs2_val; end
        endcase
    end
    assign dmem_wmask = (is_store && state == S_DECODE) ? wmask : 4'b0000;
    assign dmem_wdata = wdata;

    wire [7:0]  lb = dmem_rdata[{boff,3'b000} +: 8];
    wire [15:0] lh = boff[1] ? dmem_rdata[31:16] : dmem_rdata[15:0];
    reg [31:0] load_data;
    always @* begin
        case (funct3)
            3'b000: load_data = {{24{lb[7]}},  lb};
            3'b001: load_data = {{16{lh[15]}}, lh};
            3'b100: load_data = {24'b0, lb};
            3'b101: load_data = {16'b0, lh};
            default:load_data = dmem_rdata;
        endcase
    end

    reg br_taken;
    always @* begin
        case (funct3)
            3'b000: br_taken = (rs1_val == rs2_val);
            3'b001: br_taken = (rs1_val != rs2_val);
            3'b100: br_taken = ($signed(rs1_val) <  $signed(rs2_val));
            3'b101: br_taken = ($signed(rs1_val) >= $signed(rs2_val));
            3'b110: br_taken = (rs1_val <  rs2_val);
            3'b111: br_taken = (rs1_val >= rs2_val);
            default: br_taken = 1'b0;
        endcase
    end

    wire [31:0] pc4 = pc + 32'd4;
    reg [31:0] wb;
    always @* begin
        case (opcode)
            OP_LUI:          wb = imm_u;
            OP_AUIPC:        wb = pc + imm_u;
            OP_JAL, OP_JALR: wb = pc4;
            OP_LOAD:         wb = load_data;
            default:         wb = alu_out;
        endcase
    end
    wire writes_rd = (opcode==OP_LUI)||(opcode==OP_AUIPC)||(opcode==OP_JAL)||
                     (opcode==OP_JALR)||(opcode==OP_IMM)||(opcode==OP_REG)||(opcode==OP_LOAD);
    wire reg_we = writes_rd && (rd != 5'd0);

    reg [31:0] next_pc;
    always @* begin
        if      (opcode == OP_JAL)                next_pc = pc + imm_j;
        else if (opcode == OP_JALR)               next_pc = (rs1_val + imm_i) & ~32'd1;
        else if (opcode == OP_BRANCH && br_taken) next_pc = pc + imm_b;
        else                                      next_pc = pc4;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= S_FETCH; pc <= 32'h0; ir <= 32'h00000013;
        end else case (state)
            S_FETCH:  state <= S_DECODE;
            S_DECODE: begin ir <= imem_rdata; state <= S_EXEC; end
            S_EXEC: begin
                if (reg_we) regs[rd] <= wb;
                pc <= next_pc;
                state <= S_FETCH;
            end
            default: state <= S_FETCH;
        endcase
    end
endmodule
`default_nettype wire
