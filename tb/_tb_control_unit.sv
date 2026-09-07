`timescale 1ns/1ps

module tb_control_unit;
    logic clk = 1'b0;
    logic reset;
    logic [6:0] OpD;
    logic [2:0] Funct3D;
    logic Funct7b5D;
    logic RegWriteD;
    logic [1:0] ResultSrcD;
    logic MemWriteD;
    logic [2:0] StoreControlD;
    logic [2:0] LoadControlD;
    logic JumpD;
    logic JalrD;
    logic BranchD;
    logic [2:0] BranchControlD;
    logic [3:0] ALUControlD;
    logic ALUSrcD;
    logic ALUASrcD;
    logic [2:0] ImmSrcD;
    logic UsesRs1D;
    logic UsesRs2D;
    logic [3:0] expected_operation [0:7];

    control_unit dut (
        .clk(clk), .reset(reset), .OpD(OpD), .Funct3D(Funct3D),
        .Funct7b5D(Funct7b5D), .RegWriteD(RegWriteD), .ResultSrcD(ResultSrcD),
        .MemWriteD(MemWriteD), .StoreControlD(StoreControlD),
        .LoadControlD(LoadControlD),
        .JumpD(JumpD), .JalrD(JalrD), .BranchD(BranchD),
        .BranchControlD(BranchControlD),
        .ALUControlD(ALUControlD), .ALUSrcD(ALUSrcD),
        .ALUASrcD(ALUASrcD), .ImmSrcD(ImmSrcD),
        .UsesRs1D(UsesRs1D), .UsesRs2D(UsesRs2D)
    );

    task automatic check_control (
        input logic expected_write,
        input logic expected_alu_source,
        input logic [3:0] expected_alu
    );
        logic expected_uses_rs1;
        logic expected_uses_rs2;
        begin
            expected_uses_rs1 = 1'b0;
            expected_uses_rs2 = 1'b0;
            if (!reset && expected_write && (OpD == 7'b0010011))
                expected_uses_rs1 = 1'b1;
            if (!reset && expected_write && (OpD == 7'b0110011)) begin
                expected_uses_rs1 = 1'b1;
                expected_uses_rs2 = 1'b1;
            end

            if ((RegWriteD !== expected_write) ||
                (ALUSrcD !== expected_alu_source) ||
                (ResultSrcD !== 2'b00) || (MemWriteD !== 1'b0) ||
                (StoreControlD !== 3'b000) || (LoadControlD !== 3'b000) ||
                (JumpD !== 1'b0) || (JalrD !== 1'b0) || (BranchD !== 1'b0) ||
                (BranchControlD !== 3'b000) ||
                (ALUControlD !== expected_alu) || (ALUASrcD !== 1'b0) ||
                (ImmSrcD !== 3'b000) ||
                (UsesRs1D !== expected_uses_rs1) ||
                (UsesRs2D !== expected_uses_rs2))
                $fatal(1, "FAIL decoder: opcode=%b funct3=%b bit30=%b reset=%b",
                       OpD, Funct3D, Funct7b5D, reset);
        end
    endtask

    task automatic check_load (
        input logic [2:0] funct3,
        input logic valid
    );
        begin
            OpD = 7'b0000011;
            Funct3D = funct3;
            Funct7b5D = 1'b1; // Em I-type, este bit pertence ao imediato.
            #1;
            if (valid) begin
                if ((RegWriteD !== 1'b1) || (ResultSrcD !== 2'b01) ||
                    (MemWriteD !== 1'b0) || (StoreControlD !== 3'b000) ||
                    (LoadControlD !== funct3) ||
                    (JumpD !== 1'b0) || (JalrD !== 1'b0) ||
                    (BranchD !== 1'b0) || (BranchControlD !== 3'b000) ||
                    (ALUControlD !== 4'b0000) || (ALUSrcD !== 1'b1) ||
                    (ALUASrcD !== 1'b0) || (ImmSrcD !== 3'b000) ||
                    (UsesRs1D !== 1'b1) || (UsesRs2D !== 1'b0))
                    $fatal(1, "FAIL valid LOAD control signals funct3=%b", funct3);
            end else begin
                check_control(1'b0, 1'b0, 4'b0000);
            end
        end
    endtask

    task automatic check_store (
        input logic [2:0] funct3,
        input logic valid
    );
        begin
            OpD = 7'b0100011;
            Funct3D = funct3;
            Funct7b5D = 1'b1; // Em S-type, este bit pertence ao imediato.
            #1;
            if (valid) begin
                if ((RegWriteD !== 1'b0) || (ResultSrcD !== 2'b00) ||
                    (MemWriteD !== 1'b1) || (StoreControlD !== funct3) ||
                    (LoadControlD !== 3'b000) ||
                    (JumpD !== 1'b0) || (JalrD !== 1'b0) ||
                    (BranchD !== 1'b0) || (BranchControlD !== 3'b000) ||
                    (ALUControlD !== 4'b0000) || (ALUSrcD !== 1'b1) ||
                    (ALUASrcD !== 1'b0) || (ImmSrcD !== 3'b001) ||
                    (UsesRs1D !== 1'b1) || (UsesRs2D !== 1'b1))
                    $fatal(1, "FAIL valid STORE control signals funct3=%b", funct3);
            end else begin
                check_control(1'b0, 1'b0, 4'b0000);
            end
        end
    endtask

    task automatic check_u_type (
        input logic [6:0] opcode,
        input logic [3:0] expected_alu,
        input logic expected_alu_a_source,
        input string name
    );
        begin
            OpD = opcode;
            // Em U-type, funct3 e bit 30 pertencem ao imediato e nao ao decode.
            Funct3D = 3'b101;
            Funct7b5D = 1'b1;
            #1;
            if ((RegWriteD !== 1'b1) || (ResultSrcD !== 2'b00) ||
                (MemWriteD !== 1'b0) || (JumpD !== 1'b0) ||
                (JalrD !== 1'b0) || (BranchD !== 1'b0) ||
                (BranchControlD !== 3'b000) ||
                (ALUControlD !== expected_alu) || (ALUSrcD !== 1'b1) ||
                (ALUASrcD !== expected_alu_a_source) ||
                (ImmSrcD !== 3'b100) || UsesRs1D || UsesRs2D)
                $fatal(1, "FAIL %s control signals", name);
            $display("PASS: %s control signals", name);
        end
    endtask

    task automatic check_op_imm (
        input logic [2:0] funct3,
        input logic bit30,
        input logic [3:0] expected_alu,
        input string name
    );
        begin
            OpD = 7'b0010011;
            Funct3D = funct3;
            Funct7b5D = bit30;
            #1;
            check_control(1'b1, 1'b1, expected_alu);
            $display("PASS: %s control signals", name);
        end
    endtask

    task automatic check_op (
        input logic [2:0] funct3,
        input logic bit30,
        input logic [3:0] expected_alu,
        input string name
    );
        begin
            OpD = 7'b0110011;
            Funct3D = funct3;
            Funct7b5D = bit30;
            #1;
            check_control(1'b1, 1'b0, expected_alu);
            $display("PASS: %s control signals", name);
        end
    endtask

    task automatic check_jal;
        begin
            OpD = 7'b1101111;
            // Estes campos pertencem ao imediato J e nao alteram o decode.
            Funct3D = 3'b101;
            Funct7b5D = 1'b1;
            #1;
            if ((RegWriteD !== 1'b1) || (ResultSrcD !== 2'b10) ||
                (MemWriteD !== 1'b0) || (JumpD !== 1'b1) ||
                (JalrD !== 1'b0) ||
                (BranchD !== 1'b0) || (BranchControlD !== 3'b000) ||
                (ALUControlD !== 4'b0000) ||
                (ALUSrcD !== 1'b0) || (ImmSrcD !== 3'b011) ||
                UsesRs1D || UsesRs2D)
                $fatal(1, "FAIL JAL control signals");
            $display("PASS: JAL control signals");
        end
    endtask

    task automatic check_jalr(input logic [2:0] funct3, input logic valid);
        begin
            OpD = 7'b1100111;
            Funct3D = funct3;
            Funct7b5D = 1'b1; // Este bit pertence ao imediato I em JALR.
            #1;
            if (valid) begin
                if ((RegWriteD !== 1'b1) || (ResultSrcD !== 2'b10) ||
                    (MemWriteD !== 1'b0) || (JumpD !== 1'b1) ||
                    (JalrD !== 1'b1) || (BranchD !== 1'b0) ||
                    (BranchControlD !== 3'b000) ||
                    (ALUControlD !== 4'b0000) || (ALUSrcD !== 1'b1) ||
                    (ImmSrcD !== 3'b000) ||
                    (UsesRs1D !== 1'b1) || (UsesRs2D !== 1'b0))
                    $fatal(1, "FAIL valid JALR control signals");
            end else begin
                check_control(1'b0, 1'b0, 4'b0000);
            end
        end
    endtask

    task automatic check_branch(input logic [2:0] funct3, input logic valid);
        begin
            OpD = 7'b1100011;
            Funct3D = funct3;
            Funct7b5D = 1'b1; // No formato B, este bit pertence ao imediato.
            #1;
            if (valid) begin
                if ((RegWriteD !== 1'b0) || (ResultSrcD !== 2'b00) ||
                    (MemWriteD !== 1'b0) || (JumpD !== 1'b0) ||
                    (JalrD !== 1'b0) || (BranchD !== 1'b1) ||
                    (BranchControlD !== funct3) ||
                    (ALUControlD !== 4'b0001) || (ALUSrcD !== 1'b0) ||
                    (ImmSrcD !== 3'b010) ||
                    (UsesRs1D !== 1'b1) || (UsesRs2D !== 1'b1))
                    $fatal(1, "FAIL branch control signals funct3=%b", funct3);
            end else begin
                check_control(1'b0, 1'b0, 4'b0000);
            end
        end
    endtask

    initial begin
        reset = 1'b0;
        // Tabela esperada para bit30=0, na ordem dos oito valores de funct3.
        expected_operation[0] = 4'b0000; // ADD
        expected_operation[1] = 4'b0111; // SLL
        expected_operation[2] = 4'b0101; // SLT
        expected_operation[3] = 4'b0110; // SLTU
        expected_operation[4] = 4'b0100; // XOR
        expected_operation[5] = 4'b1000; // SRL
        expected_operation[6] = 4'b0011; // OR
        expected_operation[7] = 4'b0010; // AND

        check_op_imm(3'b000, 1'b0, 4'b0000, "ADDI");
        check_op_imm(3'b001, 1'b0, 4'b0111, "SLLI");
        check_op_imm(3'b010, 1'b0, 4'b0101, "SLTI");
        check_op_imm(3'b011, 1'b0, 4'b0110, "SLTIU");
        check_op_imm(3'b100, 1'b0, 4'b0100, "XORI");
        check_op_imm(3'b101, 1'b0, 4'b1000, "SRLI");
        check_op_imm(3'b101, 1'b1, 4'b1001, "SRAI");
        check_op_imm(3'b110, 1'b0, 4'b0011, "ORI");
        check_op_imm(3'b111, 1'b0, 4'b0010, "ANDI");

        check_op(3'b000, 1'b0, 4'b0000, "ADD");
        check_op(3'b000, 1'b1, 4'b0001, "SUB");
        check_op(3'b001, 1'b0, 4'b0111, "SLL");
        check_op(3'b010, 1'b0, 4'b0101, "SLT");
        check_op(3'b011, 1'b0, 4'b0110, "SLTU");
        check_op(3'b100, 1'b0, 4'b0100, "XOR");
        check_op(3'b101, 1'b0, 4'b1000, "SRL");
        check_op(3'b101, 1'b1, 4'b1001, "SRA");
        check_op(3'b110, 1'b0, 4'b0011, "OR");
        check_op(3'b111, 1'b0, 4'b0010, "AND");
        check_load(3'b000, 1'b1); // LB
        check_load(3'b001, 1'b1); // LH
        check_load(3'b010, 1'b1); // LW
        check_load(3'b011, 1'b0); // reservado
        check_load(3'b100, 1'b1); // LBU
        check_load(3'b101, 1'b1); // LHU
        check_load(3'b110, 1'b0); // reservado
        check_load(3'b111, 1'b0); // reservado
        $display("PASS: five LOAD operations and three invalid funct3 values");
        check_store(3'b000, 1'b1); // SB
        check_store(3'b001, 1'b1); // SH
        check_store(3'b010, 1'b1); // SW
        for (integer invalid_store = 3; invalid_store < 8;
             invalid_store = invalid_store + 1)
            check_store(invalid_store[2:0], 1'b0);
        $display("PASS: SB, SH, SW and all five invalid STORE funct3 values");
        check_u_type(7'b0110111, 4'b1010, 1'b0, "LUI");
        check_u_type(7'b0010111, 4'b0000, 1'b1, "AUIPC");
        check_jal();
        check_jalr(3'b000, 1'b1);
        for (integer invalid_f3 = 1; invalid_f3 < 8; invalid_f3 = invalid_f3 + 1)
            check_jalr(invalid_f3[2:0], 1'b0);
        $display("PASS: valid JALR and all invalid funct3 values");

        check_branch(3'b000, 1'b1); // BEQ
        check_branch(3'b001, 1'b1); // BNE
        check_branch(3'b010, 1'b0); // reservado
        check_branch(3'b011, 1'b0); // reservado
        check_branch(3'b100, 1'b1); // BLT
        check_branch(3'b101, 1'b1); // BGE
        check_branch(3'b110, 1'b1); // BLTU
        check_branch(3'b111, 1'b1); // BGEU
        $display("PASS: six branch conditions and two reserved funct3 values");

        // Todas as 128 x 8 combinacoes de opcode/funct3, com bit 30 em 0 e 1.
        // OP-IMM, OP, LOAD, STORE, LUI, AUIPC, branches, JAL e JALR sao ativos.
        for (integer op = 0; op < 128; op = op + 1) begin
            for (integer f3 = 0; f3 < 8; f3 = f3 + 1) begin
                for (integer bit30 = 0; bit30 < 2; bit30 = bit30 + 1) begin
                    OpD = op[6:0];
                    Funct3D = f3[2:0];
                    Funct7b5D = bit30[0];
                    #1;
                    if (op == 3) begin
                        if ((f3 <= 2) || (f3 == 4) || (f3 == 5)) begin
                            if ((RegWriteD !== 1'b1) || (ResultSrcD !== 2'b01) ||
                                (MemWriteD !== 1'b0) ||
                                (StoreControlD !== 3'b000) ||
                                (LoadControlD !== f3[2:0]) ||
                                (JumpD !== 1'b0) || (JalrD !== 1'b0) ||
                                (BranchD !== 1'b0) ||
                                (BranchControlD !== 3'b000) ||
                                (ALUControlD !== 4'b0000) ||
                                (ALUSrcD !== 1'b1) || (ALUASrcD !== 1'b0) ||
                                (ImmSrcD !== 3'b000) ||
                                (UsesRs1D !== 1'b1) || (UsesRs2D !== 1'b0))
                                $fatal(1, "FAIL exhaustive LOAD decoder");
                        end else begin
                            check_control(1'b0, 1'b0, 4'b0000);
                        end
                    end else if (op == 35) begin
                        if (f3 <= 2) begin
                            if ((RegWriteD !== 1'b0) || (ResultSrcD !== 2'b00) ||
                                (MemWriteD !== 1'b1) ||
                                (StoreControlD !== f3[2:0]) ||
                                (LoadControlD !== 3'b000) ||
                                (JumpD !== 1'b0) || (JalrD !== 1'b0) ||
                                (BranchD !== 1'b0) ||
                                (BranchControlD !== 3'b000) ||
                                (ALUControlD !== 4'b0000) ||
                                (ALUSrcD !== 1'b1) || (ALUASrcD !== 1'b0) ||
                                (ImmSrcD !== 3'b001) ||
                                (UsesRs1D !== 1'b1) || (UsesRs2D !== 1'b1))
                                $fatal(1, "FAIL exhaustive STORE decoder");
                        end else begin
                            check_control(1'b0, 1'b0, 4'b0000);
                        end
                    end else if (op == 55) begin
                        if ((RegWriteD !== 1'b1) || (ResultSrcD !== 2'b00) ||
                            (MemWriteD !== 1'b0) || (JumpD !== 1'b0) ||
                            (JalrD !== 1'b0) || (BranchD !== 1'b0) ||
                            (BranchControlD !== 3'b000) ||
                            (ALUControlD !== 4'b1010) || (ALUSrcD !== 1'b1) ||
                            (ALUASrcD !== 1'b0) || (ImmSrcD !== 3'b100) ||
                            UsesRs1D || UsesRs2D)
                            $fatal(1, "FAIL exhaustive LUI decoder");
                    end else if (op == 23) begin
                        if ((RegWriteD !== 1'b1) || (ResultSrcD !== 2'b00) ||
                            (MemWriteD !== 1'b0) || (JumpD !== 1'b0) ||
                            (JalrD !== 1'b0) || (BranchD !== 1'b0) ||
                            (BranchControlD !== 3'b000) ||
                            (ALUControlD !== 4'b0000) || (ALUSrcD !== 1'b1) ||
                            (ALUASrcD !== 1'b1) || (ImmSrcD !== 3'b100) ||
                            UsesRs1D || UsesRs2D)
                            $fatal(1, "FAIL exhaustive AUIPC decoder");
                    end else if (op == 111) begin
                        if ((RegWriteD !== 1'b1) || (ResultSrcD !== 2'b10) ||
                            (MemWriteD !== 1'b0) || (JumpD !== 1'b1) ||
                            (JalrD !== 1'b0) ||
                            (BranchD !== 1'b0) || (BranchControlD !== 3'b000) ||
                            (ALUControlD !== 4'b0000) ||
                            (ALUSrcD !== 1'b0) || (ImmSrcD !== 3'b011) ||
                            UsesRs1D || UsesRs2D)
                            $fatal(1, "FAIL exhaustive JAL decoder");
                    end else if (op == 103) begin
                        if (f3 == 0) begin
                            if ((RegWriteD !== 1'b1) || (ResultSrcD !== 2'b10) ||
                                (MemWriteD !== 1'b0) || (JumpD !== 1'b1) ||
                                (JalrD !== 1'b1) || (BranchD !== 1'b0) ||
                                (BranchControlD !== 3'b000) ||
                                (ALUControlD !== 4'b0000) || (ALUSrcD !== 1'b1) ||
                                (ImmSrcD !== 3'b000) ||
                                (UsesRs1D !== 1'b1) || (UsesRs2D !== 1'b0))
                                $fatal(1, "FAIL exhaustive valid JALR decoder");
                        end else begin
                            check_control(1'b0, 1'b0, 4'b0000);
                        end
                    end else if (op == 99) begin
                        if ((f3 == 0) || (f3 == 1) || (f3 >= 4)) begin
                            if ((RegWriteD !== 1'b0) || (ResultSrcD !== 2'b00) ||
                                (MemWriteD !== 1'b0) || (JumpD !== 1'b0) ||
                                (JalrD !== 1'b0) || (BranchD !== 1'b1) ||
                                (BranchControlD !== f3[2:0]) ||
                                (ALUControlD !== 4'b0001) ||
                                (ALUSrcD !== 1'b0) || (ImmSrcD !== 3'b010) ||
                                (UsesRs1D !== 1'b1) || (UsesRs2D !== 1'b1))
                                $fatal(1, "FAIL exhaustive branch decoder");
                        end else begin
                            check_control(1'b0, 1'b0, 4'b0000);
                        end
                    end else if (op == 19) begin
                        if ((f3 == 1) && (bit30 == 1))
                            check_control(1'b0, 1'b0, 4'b0000);
                        else if ((f3 == 5) && (bit30 == 1))
                            check_control(1'b1, 1'b1, 4'b1001);
                        else
                            check_control(1'b1, 1'b1, expected_operation[f3]);
                    end else if (op == 51) begin
                        if (((f3 == 0) || (f3 == 5)) && (bit30 == 1))
                            check_control(1'b1, 1'b0,
                                          (f3 == 0) ? 4'b0001 : 4'b1001);
                        else if (bit30 == 0)
                            check_control(1'b1, 1'b0, expected_operation[f3]);
                        else
                            check_control(1'b0, 1'b0, 4'b0000);
                    end else begin
                        check_control(1'b0, 1'b0, 4'b0000);
                    end
                end
            end
        end
        $display("PASS: 2048 decoder combinations including LOAD, STORE, LUI, AUIPC, branches, JAL and JALR");

        // Reset deve apagar tambem um controle nao nulo, como SRAI=1001.
        check_op_imm(3'b101, 1'b1, 4'b1001, "SRAI before reset");
        reset = 1'b1;
        #1;
        check_control(1'b0, 1'b0, 4'b0000);
        reset = 1'b0;
        #1;
        check_control(1'b1, 1'b1, 4'b1001);
        // A troca de uma instrucao valida para opcode invalido deve retirar
        // imediatamente os enables e o ALUControlD anterior.
        OpD = 7'b1111111;
        #1;
        check_control(1'b0, 1'b0, 4'b0000);
        $display("PASS: decoder reset and safe defaults after a valid instruction");

`ifndef VERILATOR
        // Verificacao de quatro estados: X/Z em campos de selecao nao podem
        // reaproveitar o enable anterior. Verilator simula dados com dois estados.
        check_op(3'b101, 1'b0, 4'b1000, "SRL before unknown bit30");
        Funct7b5D = 1'bx;
        #1;
        check_control(1'b0, 1'b0, 4'b0000);
        Funct3D = 3'bxxx;
        #1;
        check_control(1'b0, 1'b0, 4'b0000);
        OpD = 7'bzzzzzzz;
        #1;
        check_control(1'b0, 1'b0, 4'b0000);
        $display("PASS: unknown control fields keep safe defaults");
`endif
        $finish;
    end
endmodule
