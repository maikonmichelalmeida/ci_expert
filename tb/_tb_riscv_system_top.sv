`timescale 1ns/1ps

module tb_riscv_system_top;

    logic clk;
    logic reset;
    logic [31:0] alu_a;
    logic [31:0] alu_b;
    logic [3:0]  alu_op;
    logic [31:0] alu_result;
    logic        alu_zero;
    logic        alu_negative;
    logic        alu_carry;
    logic        alu_overflow;

    riscv_system_top dut (
        .clk          (clk),
        .reset        (reset),
        .alu_a        (alu_a),
        .alu_b        (alu_b),
        .alu_op       (alu_op),
        .alu_result   (alu_result),
        .alu_zero     (alu_zero),
        .alu_negative (alu_negative),
        .alu_carry    (alu_carry),
        .alu_overflow (alu_overflow)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $fsdbDumpfile("test.fsdb");
        $fsdbDumpvars(0, tb_riscv_system_top);
        $fsdbDumpMDA(0, tb_riscv_system_top);
    end

    // Todos os testes acessam a ULA pelas portas do topo do sistema.
    task automatic check_alu (
        input logic [3:0]  operation,
        input logic [31:0] operand_a,
        input logic [31:0] operand_b,
        input logic [31:0] expected_result,
        input logic        expected_zero,
        input logic        expected_negative,
        input logic        expected_carry,
        input logic        expected_overflow,
        input string       test_name
    );
        begin
            alu_op = operation;
            alu_a  = operand_a;
            alu_b  = operand_b;
            #1;

            if ((alu_result   !== expected_result)   ||
                (alu_zero     !== expected_zero)     ||
                (alu_negative !== expected_negative) ||
                (alu_carry    !== expected_carry)    ||
                (alu_overflow !== expected_overflow)) begin
                $fatal(1,
                    "FAIL %s: result=%h zero=%b negative=%b carry=%b overflow=%b",
                    test_name, alu_result, alu_zero, alu_negative,
                    alu_carry, alu_overflow);
            end

            $display("PASS: %s", test_name);
        end
    endtask

    initial begin
        $display("=== RV32I ALU TEST THROUGH SYSTEM TOP ===");

        reset  = 1'b1;
        alu_a  = 32'b0;
        alu_b  = 32'b0;
        alu_op = 4'b1111;
        #10;
        reset = 1'b0;
        #1;

        // Uma verificacao para cada codigo de operacao.
        check_alu(4'b0000, 32'd5,         32'd7,         32'd12,        1'b0, 1'b0, 1'b0, 1'b0, "ADD");
        check_alu(4'b0001, 32'd10,        32'd3,         32'd7,         1'b0, 1'b0, 1'b1, 1'b0, "SUB");
        check_alu(4'b0010, 32'hf0f0_f0f0, 32'h0f0f_0f0f, 32'h0000_0000, 1'b1, 1'b0, 1'b0, 1'b0, "AND");
        check_alu(4'b0011, 32'hf000_0000, 32'h0000_000f, 32'hf000_000f, 1'b0, 1'b1, 1'b0, 1'b0, "OR");
        check_alu(4'b0100, 32'haaaa_aaaa, 32'hffff_0000, 32'h5555_aaaa, 1'b0, 1'b0, 1'b0, 1'b0, "XOR");
        check_alu(4'b0101, 32'hffff_ffff, 32'd1,         32'd1,         1'b0, 1'b0, 1'b0, 1'b0, "SLT");
        check_alu(4'b0110, 32'hffff_ffff, 32'd1,         32'd0,         1'b1, 1'b0, 1'b0, 1'b0, "SLTU");
        check_alu(4'b0111, 32'd1,         32'd36,        32'd16,        1'b0, 1'b0, 1'b0, 1'b0, "SLL");
        check_alu(4'b1000, 32'h8000_0000, 32'd4,         32'h0800_0000, 1'b0, 1'b0, 1'b0, 1'b0, "SRL");
        check_alu(4'b1001, 32'h8000_0000, 32'd4,         32'hf800_0000, 1'b0, 1'b1, 1'b0, 1'b0, "SRA");
        check_alu(4'b1010, 32'h1111_1111, 32'h1234_5678, 32'h1234_5678, 1'b0, 1'b0, 1'b0, 1'b0, "PASS_B");
        check_alu(4'b1011, 32'h89ab_cdef, 32'h2222_2222, 32'h89ab_cdef, 1'b0, 1'b1, 1'b0, 1'b0, "PASS_A");
        check_alu(4'b1100, 32'd41,        32'b0,         32'd42,        1'b0, 1'b0, 1'b0, 1'b0, "INC");
        check_alu(4'b1101, 32'd42,        32'b0,         32'd41,        1'b0, 1'b0, 1'b1, 1'b0, "DEC");
        check_alu(4'b1110, 32'h0f0f_0f0f, 32'b0,         32'hf0f0_f0f0, 1'b0, 1'b1, 1'b0, 1'b0, "NOT");
        check_alu(4'b1111, 32'hffff_ffff, 32'hffff_ffff, 32'b0,         1'b1, 1'b0, 1'b0, 1'b0, "ZERO/NOP");

        // Casos de limite para acionar carry e overflow.
        check_alu(4'b0000, 32'hffff_ffff, 32'd1,         32'b0,         1'b1, 1'b0, 1'b1, 1'b0, "ADD carry");
        check_alu(4'b0000, 32'h7fff_ffff, 32'd1,         32'h8000_0000, 1'b0, 1'b1, 1'b0, 1'b1, "ADD overflow");
        check_alu(4'b0001, 32'b0,         32'd1,         32'hffff_ffff, 1'b0, 1'b1, 1'b0, 1'b0, "SUB borrow");
        check_alu(4'b0001, 32'h8000_0000, 32'd1,         32'h7fff_ffff, 1'b0, 1'b0, 1'b1, 1'b1, "SUB overflow");
        check_alu(4'b1100, 32'hffff_ffff, 32'b0,         32'b0,         1'b1, 1'b0, 1'b1, 1'b0, "INC carry");
        check_alu(4'b1100, 32'h7fff_ffff, 32'b0,         32'h8000_0000, 1'b0, 1'b1, 1'b0, 1'b1, "INC overflow");
        check_alu(4'b1101, 32'b0,         32'b0,         32'hffff_ffff, 1'b0, 1'b1, 1'b0, 1'b0, "DEC borrow");
        check_alu(4'b1101, 32'h8000_0000, 32'b0,         32'h7fff_ffff, 1'b0, 1'b0, 1'b1, 1'b1, "DEC overflow");

        $display("PASS: all operations and flags were checked through the top");
        $display("=== TEST FINISHED ===");
        $finish;
    end

endmodule
