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
    logic [3:0] expected_operation [0:7];

    control_unit dut (
        .clk(clk), .reset(reset), .OpD(OpD), .Funct3D(Funct3D),
        .Funct7b5D(Funct7b5D), .RegWriteD(RegWriteD), .ResultSrcD(ResultSrcD),
        .MemWriteD(MemWriteD), .JumpD(JumpD), .BranchD(BranchD),
        .ALUControlD(ALUControlD), .ALUSrcD(ALUSrcD), .ImmSrcD(ImmSrcD)
    );

    task automatic check_control (
        input logic expected_write,
        input logic [3:0] expected_alu
    );
        begin
            if ((RegWriteD !== expected_write) || (ALUSrcD !== expected_write) ||
                (ResultSrcD !== 2'b00) || (MemWriteD !== 1'b0) ||
                (JumpD !== 1'b0) || (BranchD !== 1'b0) ||
                (ALUControlD !== expected_alu) || (ImmSrcD !== 3'b000))
                $fatal(1, "FAIL decoder: opcode=%b funct3=%b bit30=%b reset=%b",
                       OpD, Funct3D, Funct7b5D, reset);
        end
    endtask

    task automatic check_instruction (
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
            check_control(1'b1, expected_alu);
            $display("PASS: %s control signals", name);
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

        check_instruction(3'b000, 1'b0, 4'b0000, "ADDI");
        check_instruction(3'b001, 1'b0, 4'b0111, "SLLI");
        check_instruction(3'b010, 1'b0, 4'b0101, "SLTI");
        check_instruction(3'b011, 1'b0, 4'b0110, "SLTIU");
        check_instruction(3'b100, 1'b0, 4'b0100, "XORI");
        check_instruction(3'b101, 1'b0, 4'b1000, "SRLI");
        check_instruction(3'b101, 1'b1, 4'b1001, "SRAI");
        check_instruction(3'b110, 1'b0, 4'b0011, "ORI");
        check_instruction(3'b111, 1'b0, 4'b0010, "ANDI");

        // Todas as 128 x 8 combinacoes de opcode/funct3, com bit 30 em 0 e 1.
        // Fora de OP-IMM (opcode decimal 19), nenhum caso habilita escrita.
        for (integer op = 0; op < 128; op = op + 1) begin
            for (integer f3 = 0; f3 < 8; f3 = f3 + 1) begin
                for (integer bit30 = 0; bit30 < 2; bit30 = bit30 + 1) begin
                    OpD = op[6:0];
                    Funct3D = f3[2:0];
                    Funct7b5D = bit30[0];
                    #1;
                    if ((op != 19) || ((f3 == 1) && (bit30 == 1)))
                        check_control(1'b0, 4'b0000);
                    else if ((f3 == 5) && (bit30 == 1))
                        check_control(1'b1, 4'b1001);
                    else
                        check_control(1'b1, expected_operation[f3]);
                end
            end
        end
        $display("PASS: 2048 decoder combinations, including rejected SLLI bit30=1");

        // Reset deve apagar tambem um controle nao nulo, como SRAI=1001.
        check_instruction(3'b101, 1'b1, 4'b1001, "SRAI before reset");
        reset = 1'b1;
        #1;
        check_control(1'b0, 4'b0000);
        reset = 1'b0;
        #1;
        check_control(1'b1, 4'b1001);
        // OP registrador-registrador ainda nao e suportado. A troca deve
        // retirar RegWriteD e o antigo ALUControlD sem esperar nenhum clock.
        OpD = 7'b0110011;
        #1;
        check_control(1'b0, 4'b0000);
        $display("PASS: decoder reset and safe defaults after a valid instruction");

`ifndef VERILATOR
        // Verificacao de quatro estados: X/Z em campos de selecao nao podem
        // reaproveitar o enable anterior. Verilator simula dados com dois estados.
        check_instruction(3'b101, 1'b0, 4'b1000, "SRLI before unknown bit30");
        Funct7b5D = 1'bx;
        #1;
        check_control(1'b0, 4'b0000);
        Funct3D = 3'bxxx;
        #1;
        check_control(1'b0, 4'b0000);
        OpD = 7'bzzzzzzz;
        #1;
        check_control(1'b0, 4'b0000);
        $display("PASS: unknown control fields keep safe defaults");
`endif
        $finish;
    end
endmodule
