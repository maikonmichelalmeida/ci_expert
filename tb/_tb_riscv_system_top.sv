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
    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;
    logic [4:0]  rd_addr;
    logic [31:0] rd_data;
    logic        rd_we;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    integer      i;

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
        .alu_overflow (alu_overflow),
        .rs1_addr     (rs1_addr),
        .rs2_addr     (rs2_addr),
        .rd_addr      (rd_addr),
        .rd_data      (rd_data),
        .rd_we        (rd_we),
        .rs1_data     (rs1_data),
        .rs2_data     (rs2_data)
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

    task automatic write_register (
        input logic [4:0]  address,
        input logic [31:0] data
    );
        begin
            @(negedge clk);
            rd_addr = address;
            rd_data = data;
            rd_we   = 1'b1;

            @(posedge clk);
            #1;
            rd_we = 1'b0;
        end
    endtask

    task automatic check_registers (
        input logic [4:0]  address_1,
        input logic [31:0] expected_1,
        input logic [4:0]  address_2,
        input logic [31:0] expected_2,
        input string       test_name
    );
        begin
            rs1_addr = address_1;
            rs2_addr = address_2;
            #1;

            if ((rs1_data !== expected_1) || (rs2_data !== expected_2)) begin
                $fatal(1,
                    "FAIL %s: rs1=x%0d data=%h expected=%h rs2=x%0d data=%h expected=%h",
                    test_name, address_1, rs1_data, expected_1,
                    address_2, rs2_data, expected_2);
            end

            $display("PASS: %s", test_name);
        end
    endtask

    task automatic check_system_pc (
        input logic [31:0] expected
    );
        begin
            if (dut.PCF !== expected) begin
                $fatal(1, "FAIL system PC: PCF=%h expected=%h", dut.PCF, expected);
            end
            $display("PASS: system PCF=%h", dut.PCF);
        end
    endtask

    initial begin
        $display("=== RV32I ALU TEST THROUGH SYSTEM TOP ===");

        reset  = 1'b1;
        alu_a  = 32'b0;
        alu_b  = 32'b0;
        alu_op = 4'b1111;
        rs1_addr = 5'b0;
        rs2_addr = 5'b0;
        rd_addr  = 5'b0;
        rd_data  = 32'b0;
        rd_we    = 1'b0;
        #10;
        reset = 1'b0;
        #1;

        $display("=== RV32I PC TEST THROUGH SYSTEM TOP ===");
        check_system_pc(32'h0000_0000);
        @(posedge clk);
        #1;
        check_system_pc(32'h0000_0004);
        @(posedge clk);
        #1;
        check_system_pc(32'h0000_0008);
        @(posedge clk);
        #1;
        check_system_pc(32'h0000_000c);

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

        $display("=== RV32I REGISTER FILE TEST THROUGH SYSTEM TOP ===");

        // x0 deve retornar zero antes e depois de uma tentativa de escrita.
        check_registers(5'd0, 32'b0, 5'd0, 32'b0, "x0 initial value");
        write_register(5'd0, 32'hffff_ffff);
        check_registers(5'd0, 32'b0, 5'd0, 32'b0, "x0 write protection");

        // Escreve um valor diferente em cada registrador de x1 ate x31.
        for (i = 1; i < 32; i = i + 1) begin
            write_register(i, 32'h1000_0000 + i);
        end

        // Le os 31 registradores pelas duas portas ao mesmo tempo.
        for (i = 1; i < 32; i = i + 1) begin
            check_registers(
                i,
                32'h1000_0000 + i,
                32 - i,
                32'h1000_0000 + (32 - i),
                "dual read"
            );
        end

        // Com rd_we em zero, o valor armazenado nao pode mudar.
        @(negedge clk);
        rd_addr = 5'd5;
        rd_data = 32'hdead_beef;
        rd_we   = 1'b0;
        @(posedge clk);
        #1;
        check_registers(5'd5, 32'h1000_0005, 5'd31, 32'h1000_001f,
                        "write enable disabled");

        $display("PASS: register file ports, writes and x0 were checked through the top");
        $display("=== TEST FINISHED ===");
        $finish;
    end

endmodule
