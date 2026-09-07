`timescale 1ns/1ps

// Teste end-to-end: todas as instrucoes vem da IMEM e chegam ao Register File
// pelo WB real. Cada cadeia marcada executa sem NOPs entre produtor e consumidor.
module tb_forwarding;
    localparam integer PROGRAM_WORDS = 71;
    localparam integer USEFUL_WRITES = 30;

    logic clk;
    logic reset;
    logic [31:0] reference_instruction [0:PROGRAM_WORDS-1];
    logic [31:0] reference_result [0:PROGRAM_WORDS-1];
    string       test_name [0:PROGRAM_WORDS-1];
    integer write_index;
    integer execute_index;
    integer useful_writes;
    logic [4:0] destination;

    wire [1:0] ForwardAE = dut.u_riscv_core.ForwardAE;
    wire [1:0] ForwardBE = dut.u_riscv_core.ForwardBE;
    wire        RegWriteW = dut.u_riscv_core.u_datapath.RegWriteW;
    wire [4:0]  RdW = dut.u_riscv_core.u_datapath.RdW;
    wire [31:0] ResultW = dut.u_riscv_core.u_datapath.ResultW;

    riscv_system_top #(
        .IMEM_INIT_FILE ("../mem/forwarding.hex")
    ) dut (
        .clk   (clk),
        .reset (reset)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic expect_addi (
        input integer index,
        input string name,
        input logic [11:0] immediate,
        input logic [4:0] rs1,
        input logic [4:0] rd,
        input logic [31:0] result
    );
        begin
            reference_instruction[index] = {immediate, rs1, 3'b000, rd, 7'b0010011};
            reference_result[index] = result;
            test_name[index] = name;
        end
    endtask

    task automatic expect_op (
        input integer index,
        input string name,
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [31:0] result
    );
        begin
            // O encoder R e independente do decoder e do arquivo HEX.
            reference_instruction[index] = {funct7, rs2, rs1, funct3, rd, 7'b0110011};
            reference_result[index] = result;
            test_name[index] = name;
        end
    endtask

    task automatic check_forwarding_case (
        input integer index,
        input logic [1:0] expected_a_select,
        input logic [1:0] expected_b_select,
        input logic [31:0] expected_a,
        input logic [31:0] expected_write_data,
        input logic [31:0] expected_b,
        input logic [31:0] expected_result,
        input string name
    );
        begin
            if ((dut.PCE !== (index * 32'd4)) ||
                (ForwardAE !== expected_a_select) ||
                (ForwardBE !== expected_b_select) ||
                (dut.SrcAE !== expected_a) ||
                (dut.WriteDataE !== expected_write_data) ||
                (dut.SrcBE !== expected_b) ||
                (dut.ALUResultE !== expected_result))
                $fatal(1, "FAIL %s: FwdA=%b FwdB=%b A=%h WriteData=%h B=%h result=%h",
                       name, ForwardAE, ForwardBE, dut.SrcAE,
                       dut.WriteDataE, dut.SrcBE, dut.ALUResultE);
            $display("PASS: %s -> ForwardA=%b ForwardB=%b", name, ForwardAE, ForwardBE);
        end
    endtask

    task automatic check_selected_execute_case(input integer index);
        begin
            case (index)
                // x1 esta em W e x2 esta em M: as duas fontes usam caminhos distintos.
                2: begin
                    check_forwarding_case(index, 2'b01, 2'b10, 32'd5, 32'd7,
                                          32'd7, 32'd12, "A from W and B from M");
                    if ((dut.u_riscv_core.u_datapath.RdM !== 5'd2) ||
                        (dut.ALUResultM !== 32'd7) || (RdW !== 5'd1) ||
                        (ResultW !== 32'd5))
                        $fatal(1, "FAIL: mixed-stage producer positions");
                end
                // Ordem inversa: A vem de M e B vem de W.
                9: check_forwarding_case(index, 2'b10, 2'b01, 32'd10, 32'd3,
                                         32'd3, 32'd13, "A from M and B from W");
                10: check_forwarding_case(index, 2'b10, 2'b01, 32'd13, 32'd10,
                                          32'd10, 32'd3, "immediate ALU-to-ALU dependency");

                // M e W possuem x12; o valor novo 2 em M deve vencer o valor 1 em W.
                17: begin
                    check_forwarding_case(index, 2'b10, 2'b00, 32'd2, 32'd0,
                                          32'd0, 32'd2, "EX/MEM priority over MEM/WB");
                    if ((dut.u_riscv_core.u_datapath.RdM !== 5'd12) ||
                        (dut.ALUResultM !== 32'd2) || (RdW !== 5'd12) ||
                        (ResultW !== 32'd1))
                        $fatal(1, "FAIL: priority test did not contain old/new x12");
                end

                23: check_forwarding_case(index, 2'b10, 2'b10, 32'd4, 32'd4,
                                          32'd4, 32'd8, "both operands from EX/MEM");
                30: check_forwarding_case(index, 2'b01, 2'b01, 32'd6, 32'd6,
                                          32'd6, 32'd12, "both operands from MEM/WB");

                // ForwardA corrige rs1, mas ALUSrcE preserva o imediato 3 em SrcBE.
                36: check_forwarding_case(index, 2'b10, 2'b00, 32'd5, 32'd12,
                                          32'd3, 32'd8, "dependent OP-IMM keeps immediate B");

                // A instrucao anterior tenta escrever x0; o bypass deve ignora-la.
                42: check_forwarding_case(index, 2'b00, 2'b00, 32'd0, 32'd0,
                                          32'd0, 32'd0, "x0 never forwards");

                // Os dois operandos ja foram committed: caminho normal 00/00.
                53: check_forwarding_case(index, 2'b00, 2'b00, 32'd4, 32'd6,
                                          32'd6, 32'd10, "both operands from Register File");

                // Cadeia final sem NOPs entre suas sete instrucoes.
                66: check_forwarding_case(index, 2'b01, 2'b10, 32'd2, 32'd3,
                                          32'd3, 32'd5, "chain ADD");
                67: check_forwarding_case(index, 2'b10, 2'b00, 32'd5, 32'd2,
                                          32'd2, 32'd3, "chain SUB");
                68: check_forwarding_case(index, 2'b10, 2'b00, 32'd3, 32'd3,
                                          32'd3, 32'd0, "chain XOR");
                69: check_forwarding_case(index, 2'b10, 2'b00, 32'd0, 32'd2,
                                          32'd2, 32'd2, "chain OR");
                70: check_forwarding_case(index, 2'b10, 2'b00, 32'd2, 32'd5,
                                          32'd5, 32'd7, "chain final ADD");
                default: begin
                    // Os demais ciclos continuam verificados pelo resultado de EX e WB.
                end
            endcase
        end
    endtask

    initial begin
        reset = 1'b1;
        useful_writes = 0;

        for (integer i = 0; i < PROGRAM_WORDS; i = i + 1)
            expect_addi(i, "NOP", 12'b0, 5'd0, 5'd0, 32'b0);

        expect_addi(0, "ADDI x1=5", 12'd5, 5'd0, 5'd1, 32'd5);
        expect_addi(1, "ADDI x2=7", 12'd7, 5'd0, 5'd2, 32'd7);
        expect_op(2, "ADD mixed M/W", 7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, 32'd12);

        expect_addi(7, "ADDI x8=3", 12'd3, 5'd0, 5'd8, 32'd3);
        expect_addi(8, "ADDI x9=10", 12'd10, 5'd0, 5'd9, 32'd10);
        expect_op(9, "ADD reverse M/W", 7'b0000000, 5'd8, 5'd9, 3'b000, 5'd10, 32'd13);
        expect_op(10, "SUB immediate dependency", 7'b0100000, 5'd9, 5'd10, 3'b000, 5'd11, 32'd3);

        expect_addi(15, "ADDI old x12", 12'd1, 5'd0, 5'd12, 32'd1);
        expect_addi(16, "ADDI new x12", 12'd1, 5'd12, 5'd12, 32'd2);
        expect_op(17, "ADD priority", 7'b0000000, 5'd0, 5'd12, 3'b000, 5'd13, 32'd2);

        expect_addi(22, "ADDI x14=4", 12'd4, 5'd0, 5'd14, 32'd4);
        expect_op(23, "ADD both from M", 7'b0000000, 5'd14, 5'd14, 3'b000, 5'd15, 32'd8);

        expect_addi(28, "ADDI x16=6", 12'd6, 5'd0, 5'd16, 32'd6);
        expect_addi(29, "ADDI filler", 12'd0, 5'd0, 5'd31, 32'd0);
        expect_op(30, "ADD both from W", 7'b0000000, 5'd16, 5'd16, 3'b000, 5'd17, 32'd12);

        expect_addi(35, "ADDI x1=5", 12'd5, 5'd0, 5'd1, 32'd5);
        expect_addi(36, "ADDI dependent", 12'd3, 5'd1, 5'd2, 32'd8);

        expect_addi(41, "ADDI ignored x0", 12'd123, 5'd0, 5'd0, 32'd123);
        expect_op(42, "ADD reads x0", 7'b0000000, 5'd0, 5'd0, 3'b000, 5'd1, 32'd0);

        expect_addi(47, "ADDI x23=4", 12'd4, 5'd0, 5'd23, 32'd4);
        expect_addi(48, "ADDI x24=6", 12'd6, 5'd0, 5'd24, 32'd6);
        expect_op(53, "ADD direct RF", 7'b0000000, 5'd24, 5'd23, 3'b000, 5'd25, 32'd10);

        // O setup deixa x1/x2 committed antes da cadeia. Dentro da cadeia,
        // produtores e consumidores continuam sem NOPs e exercitam os bypasses.
        expect_addi(58, "setup x1=2", 12'd2, 5'd0, 5'd1, 32'd2);
        expect_addi(59, "setup x2=3", 12'd3, 5'd0, 5'd2, 32'd3);
        expect_addi(64, "chain x1=2", 12'd2, 5'd0, 5'd1, 32'd2);
        expect_addi(65, "chain x2=3", 12'd3, 5'd0, 5'd2, 32'd3);
        expect_op(66, "chain ADD", 7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, 32'd5);
        expect_op(67, "chain SUB", 7'b0100000, 5'd1, 5'd3, 3'b000, 5'd4, 32'd3);
        expect_op(68, "chain XOR", 7'b0000000, 5'd2, 5'd4, 3'b100, 5'd5, 32'd0);
        expect_op(69, "chain OR", 7'b0000000, 5'd1, 5'd5, 3'b110, 5'd6, 32'd2);
        expect_op(70, "chain ADD final", 7'b0000000, 5'd3, 5'd6, 3'b000, 5'd7, 32'd7);

        #1;
        for (integer i = 0; i < PROGRAM_WORDS; i = i + 1) begin
            if (dut.u_instruction_memory.mem[i] !== reference_instruction[i])
                $fatal(1, "FAIL encoding word %0d: hex=%h expected=%h",
                       i, dut.u_instruction_memory.mem[i], reference_instruction[i]);
        end
        $display("PASS: forwarding program encodings checked independently");
        for (integer i = PROGRAM_WORDS; i < 512; i = i + 1)
            dut.u_instruction_memory.mem[i] = 32'h0000_0013;

        @(posedge clk);
        #1;
        if ({ForwardAE, ForwardBE} !== 4'b0000)
            $fatal(1, "FAIL: reset forwarding controls");
        @(negedge clk);
        reset = 1'b0;

        for (integer cycle = 1; cycle <= PROGRAM_WORDS + 4; cycle = cycle + 1) begin
            @(posedge clk);
            write_index = cycle - 5;
            if (write_index >= 0) begin
                destination = reference_instruction[write_index][11:7];
                if ((RegWriteW !== 1'b1) || (RdW !== destination) ||
                    (ResultW !== reference_result[write_index]))
                    $fatal(1, "FAIL %s WB: rd=%0d result=%h",
                           test_name[write_index], RdW, ResultW);
            end else if (RegWriteW !== 1'b0) begin
                $fatal(1, "FAIL: early WB enable");
            end

            #1;
            if ((write_index >= 0) && (destination != 5'd0)) begin
                if (dut.u_riscv_core.u_datapath.u_register_file.regs[destination] !==
                    reference_result[write_index])
                    $fatal(1, "FAIL %s did not commit through WB", test_name[write_index]);
                useful_writes = useful_writes + 1;
            end

            if ((dut.PCF !== (cycle * 32'd4)) ||
                (dut.InstrF !== ((cycle < PROGRAM_WORDS) ?
                                  reference_instruction[cycle] : 32'h0000_0013)))
                $fatal(1, "FAIL Fetch cycle %0d", cycle);

            execute_index = cycle - 2;
            if ((execute_index >= 0) && (execute_index < PROGRAM_WORDS)) begin
                if ((dut.PCE !== (execute_index * 32'd4)) ||
                    (dut.RdE !== reference_instruction[execute_index][11:7]) ||
                    (dut.RegWriteE !== 1'b1) ||
                    (dut.ALUResultE !== reference_result[execute_index]))
                    $fatal(1, "FAIL %s in Execute", test_name[execute_index]);
                check_selected_execute_case(execute_index);
            end

            if ({dut.u_riscv_core.StallF, dut.u_riscv_core.StallD,
                 dut.u_riscv_core.FlushD, dut.u_riscv_core.FlushE} !== 4'b0000)
                $fatal(1, "FAIL: forwarding activated stall or flush");
            if ((ForwardAE === 2'b11) || (ForwardBE === 2'b11) ||
                (dut.u_riscv_core.PCSrcE !== 1'b0) ||
                (dut.MemWriteM !== 1'b0) || (dut.u_data_memory.en !== 1'b0) ||
                (dut.u_data_memory.wstrb !== 4'b0000))
                $fatal(1, "FAIL: reserved forwarding, branch or memory activity");
        end

        if ((useful_writes != USEFUL_WRITES) ||
            (dut.RD1D !== 32'b0) || (dut.RD2D !== 32'b0))
            $fatal(1, "FAIL: write count or x0 read");
        if ((dut.u_riscv_core.u_datapath.u_register_file.regs[1] !== 32'd2) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[2] !== 32'd3) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[3] !== 32'd5) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[4] !== 32'd3) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[5] !== 32'd0) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[6] !== 32'd2) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[7] !== 32'd7))
            $fatal(1, "FAIL: final ALU chain register values");

        $display("PASS: dependent ALU chains execute without NOPs through forwarding");
        $display("PASS: 00/01/10 paths, M priority, x0 and OP-IMM immediate verified");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "FAIL: forwarding test timeout");
    end
endmodule
