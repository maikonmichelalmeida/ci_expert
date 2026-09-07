`timescale 1ns/1ps

// Todas as instrucoes vem da IMEM e escrevem pelo WB real. Os produtores
// possuem quatro NOPs antes dos consumidores: forwarding em A nao e necessario.
module tb_op_imm;
    localparam integer PROGRAM_WORDS = 27;
    localparam integer USEFUL_INSTRUCTIONS = 19;

    logic clk;
    logic reset;
    logic [31:0] reference_instruction [0:PROGRAM_WORDS-1];
    logic [31:0] reference_a [0:PROGRAM_WORDS-1];
    logic [31:0] reference_b [0:PROGRAM_WORDS-1];
    logic [31:0] reference_result [0:PROGRAM_WORDS-1];
    logic [3:0]  reference_alu [0:PROGRAM_WORDS-1];
    string       test_name [0:PROGRAM_WORDS-1];
    logic [31:0] committed;
    integer useful_writes;
    integer write_index;
    logic [4:0] destination;

    // Apelidos apenas de verificacao; nenhuma porta extra e criada no RTL.
    wire        RegWriteW = dut.u_riscv_core.u_datapath.RegWriteW;
    wire [1:0]  ResultSrcW = dut.u_riscv_core.u_datapath.ResultSrcW;
    wire [31:0] ResultW = dut.u_riscv_core.u_datapath.ResultW;
    wire [4:0]  RdW = dut.u_riscv_core.u_datapath.RdW;

    riscv_system_top #(
        .IMEM_INIT_FILE ("../mem/op_imm.hex")
    ) dut (
        .clk   (clk),
        .reset (reset)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic expect_operation (
        input integer index,
        input string name,
        input logic [11:0] immediate,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [3:0] alu_control,
        input logic [31:0] operand_a,
        input logic [31:0] result
    );
        begin
            // Encoder independente do decoder: monta os campos do formato I
            // e depois compara com o HEX realmente carregado na IMEM.
            reference_instruction[index] = {immediate, rs1, funct3, rd, 7'b0010011};
            reference_a[index] = operand_a;
            reference_b[index] = {{20{immediate[11]}}, immediate};
            reference_result[index] = result;
            reference_alu[index] = alu_control;
            test_name[index] = name;
        end
    endtask

    task automatic check_decode(input integer index);
        begin
            if ((dut.InstrD !== reference_instruction[index]) ||
                (dut.PCD !== (index * 32'd4)) ||
                (dut.PCPlus4D !== ((index + 1) * 32'd4)) ||
                (dut.RD1D !== reference_a[index]) ||
                (dut.ImmExtD !== reference_b[index]) ||
                (dut.u_riscv_core.RegWriteD !== 1'b1) ||
                (dut.u_riscv_core.ResultSrcD !== 2'b00) ||
                (dut.u_riscv_core.ALUSrcD !== 1'b1) ||
                (dut.u_riscv_core.ImmSrcD !== 3'b000) ||
                (dut.u_riscv_core.ALUControlD !== reference_alu[index]))
                $fatal(1, "FAIL %s Decode: InstrD=%h RD1D=%h ImmExtD=%h control=%b",
                       test_name[index], dut.InstrD, dut.RD1D, dut.ImmExtD,
                       dut.u_riscv_core.ALUControlD);
            if (!committed[reference_instruction[index][19:15]])
                $fatal(1, "FAIL: consumer arrived before its source was written");
        end
    endtask

    task automatic check_execute(input integer index);
        begin
            if ((dut.PCE !== (index * 32'd4)) ||
                (dut.RdE !== reference_instruction[index][11:7]) ||
                (dut.RD1E !== reference_a[index]) ||
                (dut.ImmExtE !== reference_b[index]) ||
                (dut.SrcAE !== reference_a[index]) ||
                (dut.SrcBE !== reference_b[index]) ||
                (dut.ALUControlE !== reference_alu[index]) ||
                (dut.ALUSrcE !== 1'b1) || (dut.RegWriteE !== 1'b1) ||
                (dut.ResultSrcE !== 2'b00) ||
                (dut.ALUResultE !== reference_result[index]))
                $fatal(1, "FAIL %s Execute: A=%h B=%h ALUResultE=%h",
                       test_name[index], dut.SrcAE, dut.SrcBE, dut.ALUResultE);
        end
    endtask

    task automatic check_memory(input integer index);
        begin
            if ((dut.ALUResultM !== reference_result[index]) ||
                (dut.u_riscv_core.u_datapath.RdM !== reference_instruction[index][11:7]) ||
                (dut.u_riscv_core.u_datapath.RegWriteM !== 1'b1) ||
                (dut.u_riscv_core.u_datapath.ResultSrcM !== 2'b00) ||
                (dut.u_riscv_core.u_datapath.PCPlus4M !== ((index + 1) * 32'd4)))
                $fatal(1, "FAIL %s EX/MEM", test_name[index]);
        end
    endtask

    initial begin
        reset = 1'b1;
        committed = 32'b1; // x0 ja e uma fonte valida; os demais virao do WB.
        useful_writes = 0;

        for (integer i = 0; i < PROGRAM_WORDS; i = i + 1)
            expect_operation(i, "NOP", 12'b0, 5'd0, 3'b000, 5'd0, 4'b0000, 32'b0, 32'b0);

        // Programa principal. Resultados esperados sao constantes calculadas
        // separadamente, nao uma segunda ALU que repete a implementacao.
        expect_operation( 0, "ADDI",  12'd10,  5'd0, 3'b000, 5'd1,  4'b0000, 32'd0,  32'd10);
        expect_operation( 5, "ANDI",  12'd6,   5'd1, 3'b111, 5'd2,  4'b0010, 32'd10, 32'd2);
        expect_operation( 6, "ORI",   12'd5,   5'd1, 3'b110, 5'd3,  4'b0011, 32'd10, 32'd15);
        expect_operation( 7, "XORI",  12'd3,   5'd1, 3'b100, 5'd4,  4'b0100, 32'd10, 32'd9);
        expect_operation( 8, "SLTI",  12'd11,  5'd1, 3'b010, 5'd5,  4'b0101, 32'd10, 32'd1);
        expect_operation( 9, "SLTIU", 12'd9,   5'd1, 3'b011, 5'd6,  4'b0110, 32'd10, 32'd0);
        expect_operation(10, "SLLI",  12'd2,   5'd1, 3'b001, 5'd7,  4'b0111, 32'd10, 32'd40);
        expect_operation(11, "SRLI",  12'd1,   5'd1, 3'b101, 5'd8,  4'b1000, 32'd10, 32'd5);
        expect_operation(12, "ADDI -8", 12'hff8, 5'd0, 3'b000, 5'd9, 4'b0000, 32'd0, 32'hffff_fff8);
        expect_operation(17, "SRAI -8 >> 1", 12'h401, 5'd9, 3'b101, 5'd10, 4'b1001, 32'hffff_fff8, 32'hffff_fffc);
        expect_operation(18, "SLTIU immediate -1", 12'hfff, 5'd0, 3'b011, 5'd12, 4'b0110, 32'd0, 32'd1);

        // O mesmo -8 compara de forma diferente em SLTI e SLTIU.
        expect_operation(19, "SLTI negative",  12'd0, 5'd9, 3'b010, 5'd13, 4'b0101, 32'hffff_fff8, 32'd1);
        expect_operation(20, "SLTIU negative", 12'd0, 5'd9, 3'b011, 5'd14, 4'b0110, 32'hffff_fff8, 32'd0);
        // Limites de shamt: zero mantem o operando e 31 chega ao bit de sinal.
        expect_operation(21, "SLLI shamt=0", 12'd0,   5'd1, 3'b001, 5'd15, 4'b0111, 32'd10, 32'd10);
        expect_operation(22, "SRLI shamt=0", 12'd0,   5'd9, 3'b101, 5'd16, 4'b1000, 32'hffff_fff8, 32'hffff_fff8);
        expect_operation(23, "SRAI shamt=0", 12'h400, 5'd9, 3'b101, 5'd17, 4'b1001, 32'hffff_fff8, 32'hffff_fff8);
        expect_operation(24, "SLLI shamt=31", 12'd31,  5'd5, 3'b001, 5'd18, 4'b0111, 32'd1, 32'h8000_0000);
        expect_operation(25, "SRLI shamt=31", 12'd31,  5'd9, 3'b101, 5'd19, 4'b1000, 32'hffff_fff8, 32'd1);
        expect_operation(26, "SRAI shamt=31", 12'h41f, 5'd9, 3'b101, 5'd20, 4'b1001, 32'hffff_fff8, 32'hffff_ffff);

        #1; // O $readmemh da IMEM executa no inicio da simulacao.
        for (integer i = 0; i < PROGRAM_WORDS; i = i + 1) begin
            if (dut.u_instruction_memory.mem[i] !== reference_instruction[i])
                $fatal(1, "FAIL independent encoding check at word %0d: hex=%h expected=%h",
                       i, dut.u_instruction_memory.mem[i], reference_instruction[i]);
        end
        $display("PASS: all program encodings checked independently by I-format fields");
        // Completa apenas a cauda da IMEM com NOPs para esvaziar o pipeline.
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
            // Antes da NBA, o banco recebe o WB do ciclo anterior. A primeira
            // instrucao chega a W no ciclo 4 e e escrita no banco no ciclo 5.
            write_index = cycle - 5;
            if (write_index >= 0) begin
                destination = reference_instruction[write_index][11:7];
                if ((RegWriteW !== 1'b1) || (ResultSrcW !== 2'b00) ||
                    (RdW !== destination) || (ResultW !== reference_result[write_index]) ||
                    (dut.u_riscv_core.u_datapath.ALUResultW !== reference_result[write_index]) ||
                    (dut.u_riscv_core.u_datapath.PCPlus4W !== ((write_index + 1) * 32'd4)))
                    $fatal(1, "FAIL %s WB before write: rd=%0d ResultW=%h",
                           test_name[write_index], RdW, ResultW);
            end else if (RegWriteW !== 1'b0) begin
                $fatal(1, "FAIL: write enabled before the first instruction reached WB");
            end

            #1; // Agora o banco e os registradores de pipeline ja foram atualizados.
            if ((write_index >= 0) && (destination != 5'd0)) begin
                if (dut.u_riscv_core.u_datapath.u_register_file.regs[destination] !== reference_result[write_index])
                    $fatal(1, "FAIL %s: Register File did not receive WB", test_name[write_index]);
                committed[destination] = 1'b1;
                useful_writes = useful_writes + 1;
                $display("PASS: %s through IF/ID/EX/MEM/WB -> x%0d=%h",
                         test_name[write_index], destination, reference_result[write_index]);
            end

            if ((dut.PCF !== (cycle * 32'd4)) ||
                (dut.InstrF !== ((cycle < PROGRAM_WORDS) ? reference_instruction[cycle] : 32'h0000_0013)))
                $fatal(1, "FAIL Fetch at cycle %0d", cycle);
            if (cycle - 1 < PROGRAM_WORDS) check_decode(cycle - 1);
            if ((cycle >= 2) && (cycle - 2 < PROGRAM_WORDS)) check_execute(cycle - 2);
            if ((cycle >= 3) && (cycle - 3 < PROGRAM_WORDS)) check_memory(cycle - 3);

            if ({dut.u_riscv_core.StallF, dut.u_riscv_core.StallD,
                 dut.u_riscv_core.FlushD, dut.u_riscv_core.FlushE} !== 4'b0)
                $fatal(1, "FAIL: stall/flush must stay neutral");
            // Os bits de imediato tambem ocupam a posicao de Rs2E. Por isso
            // ForwardBE pode mudar sem afetar SrcBE, que ALUSrcE mantem no imediato.
            if (dut.u_riscv_core.ForwardAE !== 2'b00)
                $fatal(1, "FAIL: unexpected forwarding on OP-IMM operand A");
            if ((dut.u_riscv_core.PCSrcE !== 1'b0) ||
                (dut.SrcAE !== dut.RD1E) ||
                (dut.u_riscv_core.MemWriteD !== 1'b0) || (dut.MemWriteE !== 1'b0) ||
                (dut.MemWriteM !== 1'b0) || (dut.u_data_memory.en !== 1'b0) ||
                (dut.u_data_memory.wstrb !== 4'b0) ||
                (dut.u_riscv_core.JumpD !== 1'b0) || (dut.u_riscv_core.BranchD !== 1'b0) ||
                (dut.JumpE !== 1'b0) || (dut.BranchE !== 1'b0))
                $fatal(1, "FAIL: unexpected branch or memory control");
        end

        for (integer i = 0; i < PROGRAM_WORDS; i = i + 1) begin
            destination = reference_instruction[i][11:7];
            if ((destination != 5'd0) &&
                (dut.u_riscv_core.u_datapath.u_register_file.regs[destination] !== reference_result[i]))
                $fatal(1, "FAIL final value of x%0d", destination);
        end
        if ((useful_writes != USEFUL_INSTRUCTIONS) ||
            (dut.RD1D !== 32'b0) || (dut.RD2D !== 32'b0))
            $fatal(1, "FAIL: missing writes or x0 protection");
        $display("PASS: all 9 OP-IMM instructions and 19 useful WB writes; stalls/flushes inactive");
        $finish;
    end

    initial begin
        #2000;
        $fatal(1, "FAIL: OP-IMM test timeout");
    end
endmodule
