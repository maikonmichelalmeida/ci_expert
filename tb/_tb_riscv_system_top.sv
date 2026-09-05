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
    logic [4:0]  rd_addr;
    logic [31:0] rd_data;
    logic        rd_we;

    riscv_system_top #(
        .IMEM_INIT_FILE ("../mem/program.hex")
    ) dut (
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
        .rd_addr      (rd_addr),
        .rd_data      (rd_data),
        .rd_we        (rd_we)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

`ifndef VERILATOR
    initial begin
        $fsdbDumpfile("test.fsdb");
        $fsdbDumpvars(0, tb_riscv_system_top);
        $fsdbDumpMDA(0, tb_riscv_system_top);
    end
`endif

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

    task automatic check_decode_addi;
        begin
            #1;
            if ((dut.OpD     !== 7'b0010011) ||
                (dut.Rs1D    !== 5'd0)       ||
                (dut.RdD     !== 5'd1)       ||
                (dut.Funct3D !== 3'b000)) begin
                $fatal(1,
                    "FAIL ADDI fields: OpD=%b Rs1D=%0d RdD=%0d Funct3D=%b",
                    dut.OpD, dut.Rs1D, dut.RdD, dut.Funct3D);
            end
            if (dut.RD1D !== 32'b0) begin
                $fatal(1, "FAIL ADDI register read: RD1D=%h expected=00000000",
                       dut.RD1D);
            end
            $display("PASS Decode: ADDI fields and x0 read");
        end
    endtask

    task automatic check_decode_add;
        begin
            #1;
            if ((dut.OpD       !== 7'b0110011) ||
                (dut.Rs1D      !== 5'd1)       ||
                (dut.Rs2D      !== 5'd2)       ||
                (dut.RdD       !== 5'd3)       ||
                (dut.Funct3D   !== 3'b000)     ||
                (dut.Funct7b5D !== 1'b0)) begin
                $fatal(1,
                    "FAIL ADD fields: OpD=%b Rs1D=%0d Rs2D=%0d RdD=%0d Funct3D=%b Funct7b5D=%b",
                    dut.OpD, dut.Rs1D, dut.Rs2D, dut.RdD,
                    dut.Funct3D, dut.Funct7b5D);
            end
            if ((dut.RD1D !== 32'h1111_1111) ||
                (dut.RD2D !== 32'h2222_2222)) begin
                $fatal(1,
                    "FAIL ADD register reads: RD1D=%h RD2D=%h",
                    dut.RD1D, dut.RD2D);
            end
            $display("PASS Decode: ADD fields and x1/x2 reads");
        end
    endtask

    task automatic check_structural_control_defaults;
        begin
            #1;
            // Nesta etapa, control_unit e hazard_unit devem apenas manter
            // valores neutros. O acesso hierarquico verifica as conexoes reais
            // dentro do core sem transformar esses fios em portas de produto.
            if ((dut.u_riscv_core.RegWriteD   !== 1'b0)  ||
                (dut.u_riscv_core.ResultSrcD  !== 2'b00) ||
                (dut.u_riscv_core.MemWriteD   !== 1'b0)  ||
                (dut.u_riscv_core.JumpD       !== 1'b0)  ||
                (dut.u_riscv_core.BranchD     !== 1'b0)  ||
                (dut.u_riscv_core.ALUControlD !== 3'b000)||
                (dut.u_riscv_core.ALUSrcD     !== 1'b0)  ||
                (dut.u_riscv_core.ImmSrcD     !== 3'b000)) begin
                $fatal(1, "FAIL: control_unit outputs are not neutral");
            end

            if ((dut.u_riscv_core.StallF    !== 1'b0)  ||
                (dut.u_riscv_core.StallD    !== 1'b0)  ||
                (dut.u_riscv_core.FlushD    !== 1'b0)  ||
                (dut.u_riscv_core.FlushE    !== 1'b0)  ||
                (dut.u_riscv_core.ForwardAE !== 2'b00) ||
                (dut.u_riscv_core.ForwardBE !== 2'b00)) begin
                $fatal(1, "FAIL: hazard_unit outputs are not neutral");
            end
            $display("PASS: control_unit and hazard_unit outputs are neutral");
        end
    endtask

    task automatic check_fetch (
        input logic [31:0] expected_pcf,
        input logic [31:0] expected_instrf,
        input logic [31:0] expected_instrd,
        input logic [31:0] expected_pcd,
        input logic [31:0] expected_pcplus4d
    );
        begin
            if ((dut.PCF      !== expected_pcf)      ||
                (dut.PCPlus4F !== (expected_pcf + 32'd4)) ||
                (dut.InstrF   !== expected_instrf)   ||
                (dut.InstrD   !== expected_instrd)   ||
                (dut.PCD      !== expected_pcd)      ||
                (dut.PCPlus4D !== expected_pcplus4d)) begin
                $fatal(1,
                    "FAIL Fetch: PCF=%h InstrF=%h InstrD=%h PCD=%h PCPlus4D=%h",
                    dut.PCF, dut.InstrF, dut.InstrD, dut.PCD, dut.PCPlus4D);
            end
            $display("PASS Fetch: PCF=%h InstrF=%h InstrD=%h PCD=%h PCPlus4D=%h",
                     dut.PCF, dut.InstrF, dut.InstrD, dut.PCD, dut.PCPlus4D);
        end
    endtask

    initial begin
        $display("=== RV32I SYSTEM TEST THROUGH TOP ===");

        reset  = 1'b1;
        alu_a  = 32'b0;
        alu_b  = 32'b0;
        alu_op = 4'b1111;
        rd_addr  = 5'b0;
        rd_data  = 32'b0;
        rd_we    = 1'b0;

        $display("=== TEMPORARY REGISTER FILE WRITE TEST ===");

        // O PC e o IF/ID continuam em reset enquanto o caminho temporario de
        // escrita prepara os valores que a instrucao ADD lera em x1 e x2.
        write_register(5'd0, 32'hffff_ffff);
        write_register(5'd1, 32'h1111_1111);
        write_register(5'd2, 32'h2222_2222);

        // Tenta sobrescrever x1 com rd_we=0. A leitura posterior deve manter
        // 0x1111_1111, confirmando que o enable de escrita continua funcionando.
        @(negedge clk);
        rd_addr = 5'd1;
        rd_data = 32'hdead_beef;
        rd_we   = 1'b0;
        @(posedge clk);
        #1;

        @(negedge clk);
        reset = 1'b0;
        #1;

        check_structural_control_defaults();

        $display("=== RV32I FETCH TEST THROUGH SYSTEM TOP ===");

        // Antes do primeiro avanco, InstrF ja enxerga PCF=0 de forma
        // combinacional, enquanto o registrador IF/ID continua limpo.
        check_fetch(32'h0000_0000, 32'h0010_0093, 32'b0,
                    32'b0, 32'b0);
        @(posedge clk);
        #1;
        check_fetch(32'h0000_0004, 32'h0020_0113, 32'h0010_0093,
                    32'h0000_0000, 32'h0000_0004);
        check_decode_addi();
        @(posedge clk);
        #1;
        check_fetch(32'h0000_0008, 32'h0020_81b3, 32'h0020_0113,
                    32'h0000_0004, 32'h0000_0008);
        @(posedge clk);
        #1;
        check_fetch(32'h0000_000c, 32'h0000_0013, 32'h0020_81b3,
                    32'h0000_0008, 32'h0000_000c);
        check_decode_add();

        $display("PASS: register file writes and instruction-driven reads were checked");

        $display("=== RV32I ALU TEST THROUGH SYSTEM TOP ===");

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
