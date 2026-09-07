`timescale 1ns/1ps

// O programa prepara os operandos com ADDI e depois envia instrucoes OP
// independentes uma por ciclo. Assim o pipeline fica cheio sem esconder RAW.
module tb_op;
    localparam integer PROGRAM_WORDS = 34;
    localparam integer USEFUL_INSTRUCTIONS = 18;

    logic clk;
    logic reset;
    logic [31:0] reference_instruction [0:PROGRAM_WORDS-1];
    logic [31:0] reference_a [0:PROGRAM_WORDS-1];
    logic [31:0] reference_b [0:PROGRAM_WORDS-1];
    logic [31:0] reference_result [0:PROGRAM_WORDS-1];
    logic [3:0]  reference_alu [0:PROGRAM_WORDS-1];
    logic        reference_is_op [0:PROGRAM_WORDS-1];
    string       test_name [0:PROGRAM_WORDS-1];
    logic [31:0] committed;
    logic        overlap_confirmed;
    integer useful_writes;
    integer write_index;
    logic [4:0] destination;

    // Apelidos locais apenas para as verificacoes; nao existem portas de debug.
    wire        RegWriteW  = dut.u_riscv_core.u_datapath.RegWriteW;
    wire [1:0]  ResultSrcW = dut.u_riscv_core.u_datapath.ResultSrcW;
    wire [31:0] ResultW    = dut.u_riscv_core.u_datapath.ResultW;
    wire [4:0]  RdW        = dut.u_riscv_core.u_datapath.RdW;

    riscv_system_top #(
        .IMEM_INIT_FILE ("../mem/op.hex")
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
        input logic [31:0] operand_a,
        input logic [31:0] result
    );
        begin
            // Encoder I independente da control_unit, usado nos produtores e NOPs.
            reference_instruction[index] = {immediate, rs1, 3'b000, rd, 7'b0010011};
            reference_a[index] = operand_a;
            reference_b[index] = {{20{immediate[11]}}, immediate};
            reference_result[index] = result;
            reference_alu[index] = 4'b0000;
            reference_is_op[index] = 1'b0;
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
        input logic [3:0] alu_control,
        input logic [31:0] operand_a,
        input logic [31:0] operand_b,
        input logic [31:0] result
    );
        begin
            // Encoder R independente: a palavra vem somente dos campos oficiais.
            reference_instruction[index] = {funct7, rs2, rs1, funct3, rd, 7'b0110011};
            reference_a[index] = operand_a;
            reference_b[index] = operand_b;
            reference_result[index] = result;
            reference_alu[index] = alu_control;
            reference_is_op[index] = 1'b1;
            test_name[index] = name;
        end
    endtask

    task automatic check_decode(input integer index);
        begin
            if ((dut.InstrD !== reference_instruction[index]) ||
                (dut.PCD !== (index * 32'd4)) ||
                (dut.PCPlus4D !== ((index + 1) * 32'd4)) ||
                (dut.OpD !== reference_instruction[index][6:0]) ||
                (dut.RdD !== reference_instruction[index][11:7]) ||
                (dut.Funct3D !== reference_instruction[index][14:12]) ||
                (dut.Rs1D !== reference_instruction[index][19:15]) ||
                (dut.Rs2D !== reference_instruction[index][24:20]) ||
                (dut.Funct7b5D !== reference_instruction[index][30]) ||
                (dut.RD1D !== reference_a[index]) ||
                (dut.u_riscv_core.RegWriteD !== 1'b1) ||
                (dut.u_riscv_core.ResultSrcD !== 2'b00) ||
                (dut.u_riscv_core.MemWriteD !== 1'b0) ||
                (dut.u_riscv_core.JumpD !== 1'b0) ||
                (dut.u_riscv_core.BranchD !== 1'b0) ||
                (dut.u_riscv_core.ImmSrcD !== 3'b000) ||
                (dut.u_riscv_core.ALUControlD !== reference_alu[index]))
                $fatal(1, "FAIL %s Decode at PC=%h", test_name[index], dut.PCD);

            if (reference_is_op[index]) begin
                if ((dut.RD2D !== reference_b[index]) ||
                    (dut.u_riscv_core.ALUSrcD !== 1'b0))
                    $fatal(1, "FAIL %s: second Register File port or ALUSrcD", test_name[index]);
            end else if ((dut.ImmExtD !== reference_b[index]) ||
                         (dut.u_riscv_core.ALUSrcD !== 1'b1)) begin
                $fatal(1, "FAIL %s: immediate path in Decode", test_name[index]);
            end

            if (!committed[reference_instruction[index][19:15]])
                $fatal(1, "FAIL %s: rs1 was not committed before Decode", test_name[index]);
            if (reference_is_op[index] &&
                !committed[reference_instruction[index][24:20]])
                $fatal(1, "FAIL %s: rs2 was not committed before Decode", test_name[index]);
        end
    endtask

    task automatic check_execute(input integer index);
        begin
            if ((dut.PCE !== (index * 32'd4)) ||
                (dut.Rs1E !== reference_instruction[index][19:15]) ||
                (dut.Rs2E !== reference_instruction[index][24:20]) ||
                (dut.RdE !== reference_instruction[index][11:7]) ||
                (dut.RD1E !== reference_a[index]) ||
                (dut.SrcAE !== reference_a[index]) ||
                (dut.ALUControlE !== reference_alu[index]) ||
                (dut.RegWriteE !== 1'b1) ||
                (dut.ResultSrcE !== 2'b00) ||
                (dut.MemWriteE !== 1'b0) ||
                (dut.JumpE !== 1'b0) || (dut.BranchE !== 1'b0) ||
                (dut.ALUResultE !== reference_result[index]))
                $fatal(1, "FAIL %s Execute: A=%h B=%h result=%h",
                       test_name[index], dut.SrcAE, dut.SrcBE, dut.ALUResultE);

            if (reference_is_op[index]) begin
                if ((dut.RD2E !== reference_b[index]) ||
                    (dut.WriteDataE !== reference_b[index]) ||
                    (dut.SrcBE !== reference_b[index]) ||
                    (dut.ALUSrcE !== 1'b0))
                    $fatal(1, "FAIL %s: RD2E did not reach SrcBE", test_name[index]);
            end else if ((dut.ImmExtE !== reference_b[index]) ||
                         (dut.SrcBE !== reference_b[index]) ||
                         (dut.ALUSrcE !== 1'b1)) begin
                $fatal(1, "FAIL %s: immediate did not reach SrcBE", test_name[index]);
            end
        end
    endtask

    task automatic check_memory(input integer index);
        begin
            if ((dut.ALUResultM !== reference_result[index]) ||
                (dut.u_riscv_core.u_datapath.RdM !== reference_instruction[index][11:7]) ||
                (dut.u_riscv_core.u_datapath.RegWriteM !== 1'b1) ||
                (dut.u_riscv_core.u_datapath.ResultSrcM !== 2'b00) ||
                (dut.u_riscv_core.u_datapath.MemWriteM !== 1'b0) ||
                (dut.u_riscv_core.u_datapath.PCPlus4M !== ((index + 1) * 32'd4)))
                $fatal(1, "FAIL %s EX/MEM", test_name[index]);
        end
    endtask

    task automatic check_full_pipeline_overlap;
        begin
            // No ciclo 14: IF=SLTU, ID=SLT, EX=SLL, MEM=SUB e WB=ADD.
            // Sao cinco instrucoes uteis diferentes, todas sem dependencia entre si.
            if ((dut.PCF !== 32'd56) ||
                (dut.InstrF !== reference_instruction[14]) ||
                (dut.InstrD !== reference_instruction[13]) ||
                (dut.RdD !== 5'd6) ||
                (dut.PCE !== 32'd48) || (dut.RdE !== 5'd5) ||
                (dut.ALUControlE !== 4'b0111) ||
                (dut.u_riscv_core.u_datapath.PCPlus4M !== 32'd48) ||
                (dut.u_riscv_core.u_datapath.RdM !== 5'd4) ||
                (dut.ALUResultM !== 32'd7) ||
                (dut.u_riscv_core.u_datapath.PCPlus4W !== 32'd44) ||
                (RdW !== 5'd3) || (ResultW !== 32'd13))
                $fatal(1, "FAIL: useful instructions did not overlap in IF/ID/EX/MEM/WB");
            overlap_confirmed = 1'b1;
            $display("PASS: independent OP instructions overlap correctly across the 5-stage pipeline");
        end
    endtask

    initial begin
        reset = 1'b1;
        committed = 32'b1; // x0 e sempre uma fonte valida.
        overlap_confirmed = 1'b0;
        useful_writes = 0;

        for (integer i = 0; i < PROGRAM_WORDS; i = i + 1)
            expect_addi(i, "NOP", 12'b0, 5'd0, 5'd0, 32'b0, 32'b0);

        // Produtores separados por quatro NOPs; somente o WB real prepara x1/x2.
        expect_addi(0, "ADDI x1", 12'd10, 5'd0, 5'd1, 32'd0, 32'd10);
        expect_addi(5, "ADDI x2", 12'd3, 5'd0, 5'd2, 32'd0, 32'd3);

        // Dez instrucoes independentes, sem NOPs, leem os mesmos x1 e x2.
        expect_op(10, "ADD",  7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3,  4'b0000, 32'd10, 32'd3, 32'd13);
        expect_op(11, "SUB",  7'b0100000, 5'd2, 5'd1, 3'b000, 5'd4,  4'b0001, 32'd10, 32'd3, 32'd7);
        expect_op(12, "SLL",  7'b0000000, 5'd2, 5'd1, 3'b001, 5'd5,  4'b0111, 32'd10, 32'd3, 32'd80);
        expect_op(13, "SLT",  7'b0000000, 5'd2, 5'd1, 3'b010, 5'd6,  4'b0101, 32'd10, 32'd3, 32'd0);
        expect_op(14, "SLTU", 7'b0000000, 5'd2, 5'd1, 3'b011, 5'd7,  4'b0110, 32'd10, 32'd3, 32'd0);
        expect_op(15, "XOR",  7'b0000000, 5'd2, 5'd1, 3'b100, 5'd8,  4'b0100, 32'd10, 32'd3, 32'd9);
        expect_op(16, "SRL",  7'b0000000, 5'd2, 5'd1, 3'b101, 5'd9,  4'b1000, 32'd10, 32'd3, 32'd1);
        expect_op(17, "SRA",  7'b0100000, 5'd2, 5'd1, 3'b101, 5'd10, 4'b1001, 32'd10, 32'd3, 32'd1);
        expect_op(18, "OR",   7'b0000000, 5'd2, 5'd1, 3'b110, 5'd11, 4'b0011, 32'd10, 32'd3, 32'd11);
        expect_op(19, "AND",  7'b0000000, 5'd2, 5'd1, 3'b111, 5'd12, 4'b0010, 32'd10, 32'd3, 32'd2);

        expect_addi(20, "ADDI x13=-8", 12'hff8, 5'd0, 5'd13, 32'd0, 32'hffff_fff8);
        expect_addi(25, "ADDI x14=1",  12'd1,   5'd0, 5'd14, 32'd0, 32'd1);

        // Signed/unsigned e shifts logico/aritmetico usam os mesmos operandos.
        expect_op(30, "SLT negative",  7'b0000000, 5'd14, 5'd13, 3'b010, 5'd15, 4'b0101,
                  32'hffff_fff8, 32'd1, 32'd1);
        expect_op(31, "SLTU negative", 7'b0000000, 5'd14, 5'd13, 3'b011, 5'd16, 4'b0110,
                  32'hffff_fff8, 32'd1, 32'd0);
        expect_op(32, "SRL negative",  7'b0000000, 5'd14, 5'd13, 3'b101, 5'd17, 4'b1000,
                  32'hffff_fff8, 32'd1, 32'h7fff_fffc);
        expect_op(33, "SRA negative",  7'b0100000, 5'd14, 5'd13, 3'b101, 5'd18, 4'b1001,
                  32'hffff_fff8, 32'd1, 32'hffff_fffc);

        #1; // Confere o arquivo HEX contra os dois encoders independentes.
        for (integer i = 0; i < PROGRAM_WORDS; i = i + 1) begin
            if (dut.u_instruction_memory.mem[i] !== reference_instruction[i])
                $fatal(1, "FAIL encoding at word %0d: hex=%h expected=%h",
                       i, dut.u_instruction_memory.mem[i], reference_instruction[i]);
        end
        $display("PASS: all OP and producer encodings checked independently");
        for (integer i = PROGRAM_WORDS; i < 512; i = i + 1)
            dut.u_instruction_memory.mem[i] = 32'h0000_0013;

        @(posedge clk);
        #1;
        if ((RegWriteW !== 1'b0) || (dut.MemWriteM !== 1'b0))
            $fatal(1, "FAIL reset write enables");
        @(negedge clk);
        reset = 1'b0;
        #1;
        if ((dut.PCF !== 32'b0) || (dut.InstrF !== reference_instruction[0]))
            $fatal(1, "FAIL first Fetch instruction");

        for (integer cycle = 1; cycle <= PROGRAM_WORDS + 4; cycle = cycle + 1) begin
            @(posedge clk);
            // Antes da NBA, o banco recebe a instrucao que estava em WB.
            write_index = cycle - 5;
            if (write_index >= 0) begin
                destination = reference_instruction[write_index][11:7];
                if ((RegWriteW !== 1'b1) || (ResultSrcW !== 2'b00) ||
                    (RdW !== destination) || (ResultW !== reference_result[write_index]) ||
                    (dut.u_riscv_core.u_datapath.ALUResultW !== reference_result[write_index]) ||
                    (dut.u_riscv_core.u_datapath.PCPlus4W !== ((write_index + 1) * 32'd4)))
                    $fatal(1, "FAIL %s WB before write", test_name[write_index]);
            end else if (RegWriteW !== 1'b0) begin
                $fatal(1, "FAIL: write enabled before the first instruction reached WB");
            end

            #1; // Banco e registradores de pipeline ja receberam o flanco.
            if ((write_index >= 0) && (destination != 5'd0)) begin
                if (dut.u_riscv_core.u_datapath.u_register_file.regs[destination] !==
                    reference_result[write_index])
                    $fatal(1, "FAIL %s: Register File did not receive WB", test_name[write_index]);
                committed[destination] = 1'b1;
                useful_writes = useful_writes + 1;
                $display("PASS: %s through IF/ID/EX/MEM/WB -> x%0d=%h",
                         test_name[write_index], destination, reference_result[write_index]);
            end

            if ((dut.PCF !== (cycle * 32'd4)) ||
                (dut.InstrF !== ((cycle < PROGRAM_WORDS) ?
                                  reference_instruction[cycle] : 32'h0000_0013)))
                $fatal(1, "FAIL Fetch at cycle %0d", cycle);
            if (cycle - 1 < PROGRAM_WORDS) check_decode(cycle - 1);
            if ((cycle >= 2) && (cycle - 2 < PROGRAM_WORDS)) check_execute(cycle - 2);
            if ((cycle >= 3) && (cycle - 3 < PROGRAM_WORDS)) check_memory(cycle - 3);
            if (cycle == 14) check_full_pipeline_overlap();

            if ({dut.u_riscv_core.StallF, dut.u_riscv_core.StallD,
                 dut.u_riscv_core.FlushD, dut.u_riscv_core.FlushE,
                 dut.u_riscv_core.ForwardAE, dut.u_riscv_core.ForwardBE} !== 8'b0)
                $fatal(1, "FAIL: hazard_unit must stay neutral");
            if ((dut.u_riscv_core.PCSrcE !== 1'b0) ||
                (dut.SrcAE !== dut.RD1E) || (dut.WriteDataE !== dut.RD2E) ||
                (dut.u_riscv_core.MemWriteD !== 1'b0) || (dut.MemWriteE !== 1'b0) ||
                (dut.MemWriteM !== 1'b0) || (dut.u_data_memory.en !== 1'b0) ||
                (dut.u_data_memory.wstrb !== 4'b0) ||
                (dut.u_riscv_core.JumpD !== 1'b0) || (dut.u_riscv_core.BranchD !== 1'b0) ||
                (dut.JumpE !== 1'b0) || (dut.BranchE !== 1'b0))
                $fatal(1, "FAIL: unexpected forwarding, branch or memory control");
        end

        for (integer i = 0; i < PROGRAM_WORDS; i = i + 1) begin
            destination = reference_instruction[i][11:7];
            if ((destination != 5'd0) &&
                (dut.u_riscv_core.u_datapath.u_register_file.regs[destination] !==
                 reference_result[i]))
                $fatal(1, "FAIL final value of x%0d", destination);
        end
        if ((useful_writes != USEFUL_INSTRUCTIONS) || !overlap_confirmed ||
            (dut.RD1D !== 32'b0) || (dut.RD2D !== 32'b0))
            $fatal(1, "FAIL: missing writes, overlap proof or x0 protection");
        $display("PASS: all 10 OP instructions and 18 useful WB writes; hazards/forwarding inactive");
        $finish;
    end

    initial begin
        #2500;
        $fatal(1, "FAIL: OP test timeout");
    end
endmodule
