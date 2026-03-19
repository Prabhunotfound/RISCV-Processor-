// FSM: FETCH -> FETCH_WAIT -> EXECUTE -> (MEMREAD -> MEMREAD_WAIT) -> WRITEBACK

// Instruction Decoder 
// This module decodes the instruction set and distributes the information into multiple fields
module instr_decoder (
    input  [31:0] instr,
    output [6:0]  opcode,
    output [4:0]  rd,
    output [2:0]  funct3,
    output [4:0]  rs1,
    output [4:0]  rs2,
    output        funct7b5,
    output        load_flag,
    output        store_flag,
    output        branch_flag,
    output        jal_flag,
    output        jalr_flag
);
    assign opcode   = instr[6:0];
    assign rd       = instr[11:7];
    assign funct3   = instr[14:12];
    assign rs1      = instr[19:15];
    assign rs2      = instr[24:20];
    assign funct7b5 = instr[30];
    
    // Assigning the flags based on the Op-code 
    assign load_flag   = (opcode == 7'b0000011);
    assign store_flag  = (opcode == 7'b0100011);
    assign branch_flag = (opcode == 7'b1100011);
    assign jal_flag    = (opcode == 7'b1101111);
    assign jalr_flag  = (opcode == 7'b1100111);
endmodule

// Immediate Generator
// Reconstructs the sign-extended immediate for all five RISC-V formats:
module imm_gen (
    input      [31:0] instr,
    input      [6:0]  opcode,
    output reg [31:0] imm
);
    always @(*) begin
        case (opcode)                                           
            7'b0010011,                                                             
            7'b0000011,
            7'b1100111 : imm = {{20{instr[31]}}, instr[31:20]};                       // I-type, Load-type, jalr 
            7'b0100011 : imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};          // S-type
            7'b1100011 : imm = {{19{instr[31]}}, instr[31], instr[7],                 // B-type
                                  instr[30:25], instr[11:8], 1'b0};
            7'b1101111 : imm = {{11{instr[31]}}, instr[31], instr[19:12],             // J-type
                                  instr[20], instr[30:21], 1'b0};
            7'b0110111,
            7'b0010111 : imm = {instr[31:12], 12'b0};                                 // U-type
            default    : imm = 32'b0;
        endcase
    end
endmodule

// Register File
// 32 x 32-bit registers. x0 hardwired to 0.
module reg_file (
    input        clk,
    input        rst,       // active-low
    input        wr_en,
    input  [4:0] rs1,
    input  [4:0] rs2,
    input  [4:0] rd,
    input [31:0] wr_data,
    output [31:0] rs1_data,
    output [31:0] rs2_data
);
    reg [31:0] regs [0:31];
    integer i;

    assign rs1_data = (rs1 == 5'd0) ? 32'b0 : regs[rs1];             // if the register is x0 then hard wire it to 0 
    assign rs2_data = (rs2 == 5'd0) ? 32'b0 : regs[rs2];

    always @(posedge clk) begin
        if (!rst)
            for (i = 0; i < 32; i = i + 1) regs[i] <= 32'b0;         // Reset all the registers to 0 
        else if (wr_en && (rd != 5'd0))
            regs[rd] <= wr_data;
    end
endmodule

// ALU Control
// Decides what operation needs to be executed 
module alu_control (
    input  [6:0] opcode,
    input  [2:0] funct3,
    input        funct7b5,
    output reg [3:0] alu_ctrl
);
    always @(*) begin
        case (opcode)
            7'b0000011,
            7'b0100011,
            7'b1100111,
            7'b1101111,
            7'b0010111 : alu_ctrl = 4'b0000;                                        // ADD
            7'b0110111 : alu_ctrl = 4'b1010;                                        // LUI
            7'b1100011 :
                case (funct3)
                    3'b000, 3'b001 : alu_ctrl = 4'b0001;                            // BEQ/BNE  → SUB
                    3'b100, 3'b101 : alu_ctrl = 4'b1000;                            // BLT/BGE  → SLT
                    3'b110, 3'b111 : alu_ctrl = 4'b1001;                            // BLTU/BGEU → SLTU
                    default        : alu_ctrl = 4'b0001;
                endcase
            7'b0110011,
            7'b0010011 :
                case (funct3)
                    3'b000 : alu_ctrl = (opcode[5] & funct7b5) ? 4'b0001 : 4'b0000; // ADD/SUB
                    3'b001 : alu_ctrl = 4'b0101;                                    // SLL
                    3'b010 : alu_ctrl = 4'b1000;                                    // SLT
                    3'b011 : alu_ctrl = 4'b1001;                                    // SLTU
                    3'b100 : alu_ctrl = 4'b0100;                                    // XOR
                    3'b101 : alu_ctrl = funct7b5 ? 4'b0111 : 4'b0110;               // SRA/SRL
                    3'b110 : alu_ctrl = 4'b0011;                                    // OR
                    3'b111 : alu_ctrl = 4'b0010;                                    // AND
                    default: alu_ctrl = 4'b0000;
                endcase
            default : alu_ctrl = 4'b0000;
        endcase
    end
endmodule

// ALU- It does the operation that is meant to be done taking this info from the above alu control 
module alu (
    input  [31:0] alu_a,
    input  [31:0] alu_b,
    input  [3:0]  alu_ctrl,
    output reg [31:0] alu_result,
    output            alu_zero
);
    always @(*) begin
        case (alu_ctrl)
            4'b0000 : alu_result = alu_a + alu_b;                                       // ADD
            4'b0001 : alu_result = alu_a - alu_b;                                       // SUB
            4'b0010 : alu_result = alu_a & alu_b;                                       // AND
            4'b0011 : alu_result = alu_a | alu_b;                                       // OR
            4'b0100 : alu_result = alu_a ^ alu_b;                                       // XOR
            4'b0101 : alu_result = alu_a << alu_b[4:0];                                 // SLL
            4'b0110 : alu_result = alu_a >> alu_b[4:0];                                 // SRL
            4'b0111 : alu_result = $signed(alu_a) >>> alu_b[4:0];                       // SRA
            4'b1000 : alu_result = ($signed(alu_a) < $signed(alu_b)) ? 32'd1 : 32'd0;   // SLT
            4'b1001 : alu_result = (alu_a < alu_b) ? 32'd1 : 32'd0;                     // SLTU
            4'b1010 : alu_result = alu_b;                                               // PASS
            default : alu_result = 32'b0;
        endcase
    end
    assign alu_zero = (alu_result == 32'b0);
endmodule


// Branch Logic
// Interprets the ALU result using funct3 to decide if a branch is taken.
module branch_logic (
    input  [2:0]  funct3,
    input         alu_zero,
    input  [31:0] alu_result,
    output        branch_taken
);

    assign branch_taken =
        (funct3 == 3'b000) ?  alu_zero      :                   // BEQ
        (funct3 == 3'b001) ? ~alu_zero      :                   // BNE
        (funct3 == 3'b100) ?  alu_result[0] :                   // BLT
        (funct3 == 3'b101) ? ~alu_result[0] :                   // BGE
        (funct3 == 3'b110) ?  alu_result[0] :                   // BLTU
        (funct3 == 3'b111) ? ~alu_result[0] :                   // BGEU
                              1'b0;
endmodule

// Load Data Extractor
// Extracts and sign/zero-extends byte or halfword from a 32-bit memory word.
module load_extractor (
    input  [31:0] data_reg,
    input  [1:0]  addr_low,
    input  [2:0]  funct3,
    output [31:0] load_data
);
    wire [4:0]  byte_shift = {addr_low, 3'b000};
    wire [4:0]  half_shift = {addr_low[1], 4'b0000};
    wire [7:0]  load_byte  = data_reg >> byte_shift;
    wire [15:0] load_half  = data_reg >> half_shift;

    assign load_data =
        (funct3 == 3'b000) ? {{24{load_byte[7]}},  load_byte} :             // LB
        (funct3 == 3'b001) ? {{16{load_half[15]}}, load_half} :             // LH
        (funct3 == 3'b010) ?                        data_reg  :             // LW
        (funct3 == 3'b100) ?  {24'b0,              load_byte} :             // LBU
        (funct3 == 3'b101) ?  {16'b0,              load_half} :             // LHU
                               32'b0;
endmodule


module riscv_processor #(
    parameter RESET_ADDR = 32'h00000000,
    parameter ADDR_WIDTH = 32
)(
    input         clk,
    output [31:0] mem_addr,
    output [31:0] mem_wdata,
    output [3:0]  mem_wmask,
    input  [31:0] mem_rdata,
    output        mem_rstrb,
    input         mem_rbusy,
    input         mem_wbusy,
    input         reset       // active-low
);

    localparam FETCH        = 3'd0;
    localparam FETCH_WAIT   = 3'd1;
    localparam EXECUTE      = 3'd2;
    localparam MEMREAD      = 3'd3;
    localparam MEMREAD_WAIT = 3'd4;
    localparam WRITEBACK    = 3'd5;

    // Pipeline registers
    reg [2:0]  state;
    reg [31:0] pc;
    reg [31:0] instr_reg;
    reg [31:0] data_reg;
    reg [31:0] alu_out_reg;
    reg [31:0] pc_plus4_reg;

    // Submodule wires
    wire [6:0]  opcode;
    wire [4:0]  rd, rs1, rs2;
    wire [2:0]  funct3;
    wire        funct7b5;
    wire        load_flag, store_flag, branch_flag, jal_flag, jalr_flag;
    wire [31:0] imm;
    wire [31:0] rs1_data, rs2_data;
    wire [3:0]  alu_ctrl;
    wire [31:0] alu_result;
    wire        alu_zero;
    wire        branch_taken;
    wire [31:0] load_data;

    // Register write enable
    wire reg_write_en =
        (opcode == 7'b0110011) |                        // R-type
        (opcode == 7'b0010011) |                        // I-type ALU
        (opcode == 7'b0000011) |                        // LOAD
        (opcode == 7'b1101111) |                        // JAL
        (opcode == 7'b1100111) |                        // JALR
        (opcode == 7'b0110111) |                        // LUI
        (opcode == 7'b0010111);                         // AUIPC

    wire do_reg_write = (state == WRITEBACK) && reg_write_en && (rd != 5'd0);

    // ALU input muxes
    wire [31:0] alu_a = (opcode == 7'b0010111) ? pc : rs1_data; // AUIPC uses pc
    wire [31:0] alu_b = ((opcode == 7'b0110011) || (opcode == 7'b1100011)) ? rs2_data : imm;    // R-type/branch use rs2

    // Next-PC: priority JALR > JAL > taken branch > pc+4
    wire [31:0] pc_plus4    = pc + 32'd4;
    wire [31:0] pc_branch   = pc + imm;
    wire [31:0] jalr_target = rs1_data + imm;
    wire [31:0] pc_jalr     = {jalr_target[31:1], 1'b0}; 

    wire [31:0] next_pc =
        jalr_flag                    ? pc_jalr   :
        jal_flag                     ? pc_branch :
        (branch_flag & branch_taken) ? pc_branch : pc_plus4;

    // Write-back mux
    wire [31:0] wb_result =
        load_flag              ? load_data    :
        (jal_flag | jalr_flag) ? pc_plus4_reg : alu_out_reg;

    instr_decoder decoder (
        .instr(instr_reg), .opcode(opcode), .rd(rd), .funct3(funct3),
        .rs1(rs1), .rs2(rs2), .funct7b5(funct7b5),
        .load_flag(load_flag), .store_flag(store_flag), .branch_flag(branch_flag),
        .jal_flag(jal_flag), .jalr_flag(jalr_flag)
    );

    imm_gen immgen (
        .instr(instr_reg), .opcode(opcode), .imm(imm)
    );

    reg_file regfile (
        .clk(clk), .rst(reset), .wr_en(do_reg_write),
        .rs1(rs1), .rs2(rs2), .rd(rd), .wr_data(wb_result),
        .rs1_data(rs1_data), .rs2_data(rs2_data)
    );

    alu_control alu_ctrl_unit (
        .opcode(opcode), .funct3(funct3), .funct7b5(funct7b5), .alu_ctrl(alu_ctrl)
    );

    alu alu_unit (
        .alu_a(alu_a), .alu_b(alu_b), .alu_ctrl(alu_ctrl),
        .alu_result(alu_result), .alu_zero(alu_zero)
    );

    branch_logic branch_unit (
        .funct3(funct3), .alu_zero(alu_zero),
        .alu_result(alu_result), .branch_taken(branch_taken)
    );

    load_extractor load_ext (
        .data_reg(data_reg), .addr_low(alu_out_reg[1:0]),
        .funct3(funct3), .load_data(load_data)
    );

    // Memory interface
    assign mem_addr  = ((state == FETCH) || (state == FETCH_WAIT))     ? pc          :
                       ((state == MEMREAD) || (state == MEMREAD_WAIT)) ? alu_out_reg : alu_result;
    assign mem_rstrb = (state == FETCH) || (state == MEMREAD);
    assign mem_wdata = (funct3 == 3'b000) ? {4{rs2_data[7:0]}}  :    
                       (funct3 == 3'b001) ? {2{rs2_data[15:0]}} : rs2_data;    
    assign mem_wmask = (state != EXECUTE || !store_flag) ? 4'b0000 :
                       (funct3 == 3'b000) ? (4'b0001 << alu_result[1:0])        :
                       (funct3 == 3'b001) ? (alu_result[1] ? 4'b1100 : 4'b0011) : 4'b1111;

    // Finite State Machine (FSM)
    always @(posedge clk) begin
        if (!reset) begin
            pc           <= RESET_ADDR;
            state        <= FETCH;
            instr_reg    <= 32'b0;
            data_reg     <= 32'b0;
            alu_out_reg  <= 32'b0;
            pc_plus4_reg <= 32'b0;
        end
        else begin
            case (state)
                FETCH: begin
                    state <= FETCH_WAIT;
                end

                FETCH_WAIT: begin
                    if (!mem_rbusy) begin
                        instr_reg <= mem_rdata;
                        state     <= EXECUTE;
                    end
                end

                EXECUTE: begin
                    alu_out_reg  <= alu_result;
                    pc_plus4_reg <= pc_plus4;
                    if (store_flag) begin
                        if (!mem_wbusy) begin
                            pc    <= next_pc;
                            state <= FETCH;
                        end
                    end
                    else if (load_flag) begin
                        state <= MEMREAD;
                    end
                    else begin
                        pc    <= next_pc;
                        state <= WRITEBACK;
                    end
                end

                MEMREAD: begin
                    state <= MEMREAD_WAIT;
                end

                MEMREAD_WAIT: begin
                    if (!mem_rbusy) begin
                        data_reg <= mem_rdata;
                        pc       <= next_pc;
                        state    <= WRITEBACK;
                    end
                end

                WRITEBACK: begin
                    state <= FETCH;
                end

                default: begin
                    pc           <= RESET_ADDR;
                    state        <= FETCH;
                    instr_reg    <= 32'b0;
                    data_reg     <= 32'b0;
                    alu_out_reg  <= 32'b0;
                    pc_plus4_reg <= 32'b0;
                end
            endcase
        end
    end

endmodule
