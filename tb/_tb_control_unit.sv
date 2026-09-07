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
    logic JumpD;
    logic BranchD;
    logic [3:0] ALUControlD;
    logic ALUSrcD;
    logic [2:0] ImmSrcD;

    control_unit dut (
        .clk(clk), .reset(reset), .OpD(OpD), .Funct3D(Funct3D),
        .Funct7b5D(Funct7b5D), .RegWriteD(RegWriteD), .ResultSrcD(ResultSrcD),
        .MemWriteD(MemWriteD), .JumpD(JumpD), .BranchD(BranchD),
        .ALUControlD(ALUControlD), .ALUSrcD(ALUSrcD), .ImmSrcD(ImmSrcD)
    );

    task automatic check_control(input logic expected_addi);
        begin
            if ((RegWriteD !== expected_addi) || (ALUSrcD !== expected_addi) ||
                (ResultSrcD !== 2'b00) || (MemWriteD !== 1'b0) ||
                (JumpD !== 1'b0) || (BranchD !== 1'b0) ||
                (ALUControlD !== 4'b0000) || (ImmSrcD !== 3'b000))
                $fatal(1, "FAIL decoder: opcode=%b funct3=%b bit30=%b reset=%b",
                       OpD, Funct3D, Funct7b5D, reset);
        end
    endtask

    initial begin
        reset = 1'b0;
        // Todas as 128 x 8 combinacoes de opcode/funct3, com bit 30 em 0 e 1.
        // Isso inclui os outros OP-IMM, OP, LOAD, STORE, BRANCH e JUMP.
        for (integer op = 0; op < 128; op = op + 1) begin
            for (integer f3 = 0; f3 < 8; f3 = f3 + 1) begin
                for (integer bit30 = 0; bit30 < 2; bit30 = bit30 + 1) begin
                    OpD = op[6:0];
                    Funct3D = f3[2:0];
                    Funct7b5D = bit30[0];
                    #1;
                    check_control((op == 19) && (f3 == 0));
                end
            end
        end
        $display("PASS: 2048 decoder combinations; only ADDI enables writeback");

        OpD = 7'b0010011;
        Funct3D = 3'b000;
        reset = 1'b1;
        #1;
        check_control(1'b0);
        reset = 1'b0;
        #1;
        check_control(1'b1);
        // Voltar a uma instrucao nao suportada deve remover o enable de ADDI.
        Funct3D = 3'b111;
        #1;
        check_control(1'b0);
        $display("PASS: decoder reset and safe defaults after ADDI");
        $finish;
    end
endmodule
