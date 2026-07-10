`default_nettype none
// 5-stage pipeline: IF -> ID -> EX -> MEM -> WB
// Same port list as rv32i_core.v -- drop-in replacement.
module rv32i_pipe (
    input  wire        clk,
    input  wire        rst_n,
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire [3:0]  dmem_wmask,
    input  wire [31:0] dmem_rdata
);
    localparam OP_LUI = 7'b0110111, OP_AUIPC = 7'b0010111, OP_JAL = 7'b1101111,
               OP_JALR = 7'b1100111, OP_BRANCH = 7'b1100011, OP_IMM = 7'b0010011,
               OP_REG = 7'b0110011, OP_LOAD = 7'b0000011, OP_STORE = 7'b0100011;
    localparam NOP = 32'h00000013;

    reg [31:0] regs [0:31];
    integer i;
    initial for (i=0;i<32;i=i+1) regs[i]=32'b0;

    // ================= IF =================
    reg [31:0] pc;
    reg [31:0] pcd;          // pc of the instruction currently in ID
    reg        ifid_bubble;

    // imem_rdata lags pc by one cycle (BRAM). To replay the instruction sitting
    // in ID during a stall we must re-address ITS pc, not freeze pc.
    wire stall;
    assign imem_addr = stall ? pcd : pc;

    wire [31:0] id_instr = ifid_bubble ? NOP : imem_rdata;

    // ================= ID =================
    wire [6:0] id_op   = id_instr[6:0];
    wire [4:0] id_rs1  = id_instr[19:15];
    wire [4:0] id_rs2  = id_instr[24:20];

    wire id_uses_rs1 = !(id_op==OP_LUI || id_op==OP_AUIPC || id_op==OP_JAL);
    wire id_uses_rs2 = (id_op==OP_REG || id_op==OP_BRANCH || id_op==OP_STORE);

    wire [31:0] wb_data;
    wire        wb_we;
    wire [4:0]  wb_rd;
    wire [31:0] id_rs1v = (id_rs1==5'd0) ? 32'b0 :
                          (wb_we && wb_rd==id_rs1) ? wb_data : regs[id_rs1];
    wire [31:0] id_rs2v = (id_rs2==5'd0) ? 32'b0 :
                          (wb_we && wb_rd==id_rs2) ? wb_data : regs[id_rs2];

    // ================= ID/EX =================
    reg [31:0] ex_instr, ex_pc, ex_rs1v, ex_rs2v;
    reg        ex_valid;   // 0 = bubble; replaces resetting 32 bits of ex_instr

    wire [6:0] ex_op     = ex_instr[6:0];
    wire [4:0] ex_rd     = ex_instr[11:7];
    wire [2:0] ex_funct3 = ex_instr[14:12];
    wire [4:0] ex_rs1    = ex_instr[19:15];
    wire [4:0] ex_rs2    = ex_instr[24:20];

    wire ex_is_imm   = (ex_op == OP_IMM);
    wire ex_is_reg   = (ex_op == OP_REG);
    wire ex_is_load  = (ex_op == OP_LOAD)  && ex_valid;
    wire ex_is_store = (ex_op == OP_STORE) && ex_valid;

    wire [31:0] ex_imm_i = {{20{ex_instr[31]}}, ex_instr[31:20]};
    wire [31:0] ex_imm_u = {ex_instr[31:12], 12'b0};
    wire [31:0] ex_imm_b = {{19{ex_instr[31]}}, ex_instr[31], ex_instr[7],
                            ex_instr[30:25], ex_instr[11:8], 1'b0};
    wire [31:0] ex_imm_j = {{11{ex_instr[31]}}, ex_instr[31], ex_instr[19:12],
                            ex_instr[20], ex_instr[30:21], 1'b0};
    wire [31:0] ex_imm_s = {{20{ex_instr[31]}}, ex_instr[31:25], ex_instr[11:7]};

    wire ex_writes_rd = (ex_op==OP_LUI)||(ex_op==OP_AUIPC)||(ex_op==OP_JAL)||
                        (ex_op==OP_JALR)||(ex_op==OP_IMM)||(ex_op==OP_REG)||(ex_op==OP_LOAD);
    wire ex_reg_we = ex_writes_rd && (ex_rd != 5'd0) && ex_valid;

    // ---------- forwarding ----------
    reg [31:0] mem_val;  reg [4:0] mem_rd;  reg mem_reg_we, mem_is_load;

    wire fwd1_mem = mem_reg_we && (mem_rd != 5'd0) && (mem_rd == ex_rs1) && !mem_is_load;
    wire fwd1_wb  = wb_we      && (wb_rd  != 5'd0) && (wb_rd  == ex_rs1);
    wire fwd2_mem = mem_reg_we && (mem_rd != 5'd0) && (mem_rd == ex_rs2) && !mem_is_load;
    wire fwd2_wb  = wb_we      && (wb_rd  != 5'd0) && (wb_rd  == ex_rs2);

    wire [31:0] rs1f = (ex_rs1==5'd0) ? 32'b0 : fwd1_mem ? mem_val : fwd1_wb ? wb_data : ex_rs1v;
    wire [31:0] rs2f = (ex_rs2==5'd0) ? 32'b0 : fwd2_mem ? mem_val : fwd2_wb ? wb_data : ex_rs2v;

    // ---------- ALU ----------
    wire [31:0] alu_b = ex_is_reg ? rs2f : ex_imm_i;
    wire [4:0]  shamt = ex_is_reg ? rs2f[4:0] : ex_instr[24:20];
    wire        alt   = ex_instr[30] & (ex_is_reg | (ex_is_imm & (ex_funct3==3'b101)));

    reg [31:0] alu_out;
    always @* begin
        case (ex_funct3)
            3'b000: alu_out = alt ? (rs1f - alu_b) : (rs1f + alu_b);
            3'b001: alu_out = rs1f << shamt;
            3'b010: alu_out = {31'b0, ($signed(rs1f) < $signed(alu_b))};
            3'b011: alu_out = {31'b0, (rs1f < alu_b)};
            3'b100: alu_out = rs1f ^ alu_b;
            3'b101: alu_out = alt ? ($signed(rs1f) >>> shamt) : (rs1f >> shamt);
            3'b110: alu_out = rs1f | alu_b;
            3'b111: alu_out = rs1f & alu_b;
        endcase
    end

    // ---------- branch resolution (in EX) ----------
    reg br_taken;
    always @* begin
        case (ex_funct3)
            3'b000: br_taken = (rs1f == rs2f);
            3'b001: br_taken = (rs1f != rs2f);
            3'b100: br_taken = ($signed(rs1f) <  $signed(rs2f));
            3'b101: br_taken = ($signed(rs1f) >= $signed(rs2f));
            3'b110: br_taken = (rs1f <  rs2f);
            3'b111: br_taken = (rs1f >= rs2f);
            default: br_taken = 1'b0;
        endcase
    end

    reg  [31:0] ex_target;
    reg         ex_redirect;
    always @* begin
        ex_redirect = 1'b0;
        ex_target   = 32'b0;
        if (!ex_valid) ;  // squashed slot still holds real bits: must not branch
        else if (ex_op == OP_JAL)  begin ex_redirect=1'b1; ex_target = ex_pc + ex_imm_j; end
        else if (ex_op == OP_JALR) begin ex_redirect=1'b1; ex_target = (rs1f + ex_imm_i) & ~32'd1; end
        else if (ex_op == OP_BRANCH && br_taken) begin ex_redirect=1'b1; ex_target = ex_pc + ex_imm_b; end
    end

    // ---------- address / store data ----------
    wire [31:0] ex_addr = rs1f + (ex_is_store ? ex_imm_s : ex_imm_i);
    wire [1:0]  ex_boff = ex_addr[1:0];

    reg [3:0] ex_wmask; reg [31:0] ex_wdata;
    always @* begin
        case (ex_funct3)
            3'b000: begin ex_wmask = 4'b0001 << ex_boff; ex_wdata = rs2f << (8*ex_boff); end
            3'b001: begin ex_wmask = 4'b0011 << {ex_boff[1],1'b0}; ex_wdata = rs2f << (16*ex_boff[1]); end
            default:begin ex_wmask = 4'b1111; ex_wdata = rs2f; end
        endcase
    end

    reg [31:0] ex_val;
    always @* begin
        case (ex_op)
            OP_LUI:          ex_val = ex_imm_u;
            OP_AUIPC:        ex_val = ex_pc + ex_imm_u;
            OP_JAL, OP_JALR: ex_val = ex_pc + 32'd4;
            default:         ex_val = alu_out;
        endcase
    end

    // ================= EX/MEM =================
    reg [31:0] mem_addr_r, mem_wdata_r;
    reg [3:0]  mem_wmask_r;
    reg        mem_is_store;
    reg [2:0]  mem_funct3;

    assign dmem_addr  = mem_addr_r;
    assign dmem_wdata = mem_wdata_r;
    assign dmem_wmask = mem_is_store ? mem_wmask_r : 4'b0000;

    // ================= MEM/WB =================
    reg [31:0] wb_val;
    reg [4:0]  wb_rd_r;
    reg        wb_we_r, wb_is_load;
    reg [2:0]  wb_funct3;
    reg [1:0]  wb_boff;

    wire [7:0]  lb = dmem_rdata[{wb_boff,3'b000} +: 8];
    wire [15:0] lh = wb_boff[1] ? dmem_rdata[31:16] : dmem_rdata[15:0];
    reg [31:0] load_data;
    always @* begin
        case (wb_funct3)
            3'b000: load_data = {{24{lb[7]}}, lb};
            3'b001: load_data = {{16{lh[15]}}, lh};
            3'b100: load_data = {24'b0, lb};
            3'b101: load_data = {16'b0, lh};
            default:load_data = dmem_rdata;
        endcase
    end

    assign wb_data = wb_is_load ? load_data : wb_val;
    assign wb_we   = wb_we_r;
    assign wb_rd   = wb_rd_r;

    // ================= hazard control =================
    wire load_use = ex_is_load && (ex_rd != 5'd0) && !ifid_bubble &&
                    ((id_uses_rs1 && id_rs1 == ex_rd) ||
                     (id_uses_rs2 && id_rs2 == ex_rd));

    assign stall = load_use && !ex_redirect;

    // ================= sequential =================
    always @(posedge clk) begin
        if (!rst_n) begin
            pc <= 32'h0; pcd <= 32'h0; ifid_bubble <= 1'b1;
            ex_instr <= NOP; ex_valid <= 1'b0; ex_pc <= 32'b0; ex_rs1v <= 32'b0; ex_rs2v <= 32'b0;
            mem_reg_we <= 1'b0; mem_is_load <= 1'b0; mem_is_store <= 1'b0;
            mem_rd <= 5'b0; mem_val <= 32'b0; mem_addr_r <= 32'b0;
            mem_wdata_r <= 32'b0; mem_wmask_r <= 4'b0; mem_funct3 <= 3'b0;
            wb_we_r <= 1'b0; wb_is_load <= 1'b0; wb_rd_r <= 5'b0;
            wb_val <= 32'b0; wb_funct3 <= 3'b0; wb_boff <= 2'b0;
        end else begin
            if (ex_redirect) begin
                pc          <= ex_target;
                pcd         <= pc;
                ifid_bubble <= 1'b1;
            end else if (stall) begin
                pc          <= pc;
                pcd         <= pcd;
                ifid_bubble <= ifid_bubble;
            end else begin
                pc          <= pc + 32'd4;
                pcd         <= pc;
                ifid_bubble <= 1'b0;
            end

            ex_instr <= id_instr;      // datapath flows unconditionally
            ex_pc    <= pcd;
            ex_rs1v  <= id_rs1v;
            ex_rs2v  <= id_rs2v;
            ex_valid <= !(ex_redirect || stall);

            mem_val      <= ex_val;
            mem_rd       <= ex_rd;
            mem_reg_we   <= ex_reg_we;
            mem_is_load  <= ex_is_load;
            mem_is_store <= ex_is_store;
            mem_addr_r   <= ex_addr;
            mem_wdata_r  <= ex_wdata;
            mem_wmask_r  <= ex_wmask;
            mem_funct3   <= ex_funct3;

            wb_val     <= mem_val;
            wb_rd_r    <= mem_rd;
            wb_we_r    <= mem_reg_we;
            wb_is_load <= mem_is_load;
            wb_funct3  <= mem_funct3;
            wb_boff    <= mem_addr_r[1:0];

            if (wb_we_r && wb_rd_r != 5'd0) regs[wb_rd_r] <= wb_data;
        end
    end
endmodule
`default_nettype wire
