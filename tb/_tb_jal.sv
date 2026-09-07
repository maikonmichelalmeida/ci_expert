`timescale 1ns/1ps

// Fecha o JAL no core atual: offset positivo e negativo, link por PC+4,
// consumidor imediato no alvo, JAL x0, redirect e descarte do caminho errado.
// Todos os targets executados sao multiplos de 4. Exceptions por endereco de
// instrucao desalinhado permanecem reservadas para uma etapa futura.
module tb_jal;
    localparam integer PROGRAM_WORDS = 22;

    logic clk;
    logic reset;
    logic [31:0] expected_program [0:PROGRAM_WORDS-1];
    logic [31:0] isolated_instruction;
    logic [2:0]  isolated_imm_src;
    logic [31:0] isolated_imm;
    integer redirect_count;
    integer jal_x0_wb_count;
    logic saw_positive_wb_id;
    logic saw_positive_consumer;
    logic saw_negative_execute;
    logic saw_negative_link;
    logic saw_final_forwarding;

    wire        PCSrcE     = dut.u_riscv_core.PCSrcE;
    wire        StallF     = dut.u_riscv_core.StallF;
    wire        StallD     = dut.u_riscv_core.StallD;
    wire        FlushD     = dut.u_riscv_core.FlushD;
    wire        FlushE     = dut.u_riscv_core.FlushE;
    wire [1:0]  ForwardAE  = dut.u_riscv_core.ForwardAE;
    wire [1:0]  ForwardBE  = dut.u_riscv_core.ForwardBE;
    wire        RegWriteW  = dut.u_riscv_core.u_datapath.RegWriteW;
    wire [1:0]  ResultSrcW = dut.u_riscv_core.u_datapath.ResultSrcW;
    wire [4:0]  RdW        = dut.u_riscv_core.u_datapath.RdW;
    wire [31:0] ResultW     = dut.u_riscv_core.u_datapath.ResultW;
    wire [31:0] RFRead1D   = dut.u_riscv_core.u_datapath.RFRead1D;
    wire [31:0] RFRead2D   = dut.u_riscv_core.u_datapath.RFRead2D;

    riscv_system_top #(
        .IMEM_INIT_FILE ("../mem/jal.hex")
    ) dut (
        .clk   (clk),
        .reset (reset)
    );

    // Instancia isolada apenas para conferir os limites do formato J. O fluxo
    // end-to-end abaixo continua usando o extend que pertence ao datapath.
    extend u_isolated_extend (
        .InstrD  (isolated_instruction[31:7]),
        .ImmSrcD (isolated_imm_src),
        .ImmExtD (isolated_imm)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function automatic logic [31:0] encode_addi(
        input logic [11:0] immediate,
        input logic [4:0] rs1,
        input logic [4:0] rd
    );
        encode_addi = {immediate, rs1, 3'b000, rd, 7'b0010011};
    endfunction

    function automatic logic [31:0] encode_jal(
        input integer offset,
        input logic [4:0] rd
    );
        logic [20:0] offset_bits;
        begin
            // O recorte para 21 bits conserva a representacao em complemento
            // de dois dos offsets negativos antes de distribuir o formato J.
            offset_bits = offset[20:0];
            encode_jal = {offset_bits[20], offset_bits[10:1], offset_bits[11],
                          offset_bits[19:12], rd, 7'b1101111};
        end
    endfunction

    task automatic check_isolated_j_imm(
        input integer offset,
        input logic [31:0] expected,
        input string name
    );
        begin
            isolated_instruction = encode_jal(offset, 5'd1);
            isolated_imm_src = 3'b011;
            #1;
            if (isolated_imm !== expected)
                $fatal(1, "FAIL %s: ImmExt=%h expected=%h",
                       name, isolated_imm, expected);
            $display("PASS: %s -> %h", name, isolated_imm);
        end
    endtask

    task automatic check_common;
        begin
            if ({StallF, StallD} !== 2'b00)
                $fatal(1, "FAIL: JAL nao deve produzir stall neste checkpoint");
            if ({FlushD, FlushE} !== {2{PCSrcE}})
                $fatal(1, "FAIL: FlushD/FlushE nao acompanham PCSrcE");
            if ((ForwardAE === 2'b11) || (ForwardBE === 2'b11))
                $fatal(1, "FAIL: forwarding produziu o codigo reservado 11");
            if ((dut.MemWriteM !== 1'b0) || (dut.u_data_memory.en !== 1'b0) ||
                (dut.u_data_memory.wstrb !== 4'b0000))
                $fatal(1, "FAIL: acesso inesperado a DMEM");

            // x20..x31 aparecem somente no caminho errado deste programa.
            // Detectar RegWriteW e mais forte do que confiar no valor final.
            if (RegWriteW && (RdW >= 5'd20))
                $fatal(1, "FAIL: instrucao wrong-path chegou ao WB para x%0d", RdW);
        end
    endtask

    initial begin
        reset = 1'b1;
        redirect_count = 0;
        jal_x0_wb_count = 0;
        saw_positive_wb_id = 1'b0;
        saw_positive_consumer = 1'b0;
        saw_negative_execute = 1'b0;
        saw_negative_link = 1'b0;
        saw_final_forwarding = 1'b0;
        isolated_instruction = 32'b0;
        isolated_imm_src = 3'b011;

        // Casos independentes: pequenos offsets e os dois extremos assinados.
        check_isolated_j_imm(16,       32'h0000_0010, "J +16");
        check_isolated_j_imm(-12,      32'hffff_fff4, "J -12");
        check_isolated_j_imm(1048574,  32'h000f_fffe, "J maximum positive");
        check_isolated_j_imm(-1048576, 32'hfff0_0000, "J maximum negative");

        expected_program[0]  = encode_addi(12'd5,   5'd0,  5'd5);
        expected_program[1]  = encode_jal(16,  5'd10);
        expected_program[2]  = encode_addi(12'd111, 5'd0,  5'd20);
        expected_program[3]  = encode_addi(12'd222, 5'd0,  5'd21);
        expected_program[4]  = encode_addi(12'd333, 5'd0,  5'd22);
        expected_program[5]  = encode_addi(12'd1,   5'd10, 5'd11);
        expected_program[6]  = encode_jal(16,  5'd0);
        expected_program[7]  = encode_addi(12'd55,  5'd0,  5'd23);
        expected_program[8]  = encode_addi(12'd66,  5'd0,  5'd24);
        expected_program[9]  = encode_addi(12'd77,  5'd0,  5'd25);
        expected_program[10] = encode_jal(24,  5'd0);
        expected_program[11] = encode_addi(12'd88,  5'd0,  5'd26);
        expected_program[12] = encode_addi(12'd99,  5'd0,  5'd27);
        expected_program[13] = encode_addi(12'd7,   5'd0,  5'd7);
        expected_program[14] = encode_jal(24,  5'd0);
        expected_program[15] = encode_addi(12'd110, 5'd0,  5'd28);
        expected_program[16] = encode_jal(-12, 5'd6);
        expected_program[17] = encode_addi(12'd121, 5'd0,  5'd29);
        expected_program[18] = encode_addi(12'd122, 5'd0,  5'd30);
        expected_program[19] = encode_addi(12'd123, 5'd0,  5'd31);
        expected_program[20] = encode_addi(12'd1,   5'd6,  5'd8);
        expected_program[21] = encode_addi(12'd1,   5'd8,  5'd9);

        #1;
        for (integer i = 0; i < PROGRAM_WORDS; i = i + 1) begin
            if (dut.u_instruction_memory.mem[i] !== expected_program[i])
                $fatal(1, "FAIL encoding word %0d: hex=%h expected=%h",
                       i, dut.u_instruction_memory.mem[i], expected_program[i]);
        end
        for (integer i = PROGRAM_WORDS; i < 512; i = i + 1)
            dut.u_instruction_memory.mem[i] = 32'h0000_0013;
        $display("PASS: complete JAL program encoding checked independently");

        @(posedge clk);
        #1;
        if ((dut.PCF !== 32'b0) || (RegWriteW !== 1'b0))
            $fatal(1, "FAIL reset state");

        @(negedge clk);
        reset = 1'b0;

        for (integer cycle = 1; cycle <= 50; cycle = cycle + 1) begin
            @(posedge clk);
            #1;
            check_common();

            if (PCSrcE) begin
                redirect_count = redirect_count + 1;
                case (dut.PCE)
                    32'd4: begin
                        if ((dut.ImmExtE !== 32'd16) ||
                            (dut.PCTargetE !== 32'd20) || (dut.RdE !== 5'd10) ||
                            (dut.PCPlus4E !== 32'd8))
                            $fatal(1, "FAIL positive JAL Execute");
                    end
                    32'd24: begin
                        if ((dut.ImmExtE !== 32'd16) ||
                            (dut.PCTargetE !== 32'd40) || (dut.RdE !== 5'd0))
                            $fatal(1, "FAIL first JAL x0 Execute");
                    end
                    32'd40: begin
                        if ((dut.ImmExtE !== 32'd24) ||
                            (dut.PCTargetE !== 32'd64) || (dut.RdE !== 5'd0))
                            $fatal(1, "FAIL jump to backward JAL");
                    end
                    32'd64: begin
                        if ((dut.ImmExtE !== 32'hffff_fff4) ||
                            (dut.PCTargetE !== 32'd52) || (dut.RdE !== 5'd6) ||
                            (dut.PCPlus4E !== 32'd68))
                            $fatal(1, "FAIL negative JAL Execute");
                        saw_negative_execute = 1'b1;
                        $display("PASS: JAL at PC=64 uses offset=-12 and target=52");
                    end
                    32'd56: begin
                        if ((dut.ImmExtE !== 32'd24) ||
                            (dut.PCTargetE !== 32'd80) || (dut.RdE !== 5'd0))
                            $fatal(1, "FAIL exit from backward target");
                    end
                    default: $fatal(1, "FAIL unexpected redirect from PC=%0d", dut.PCE);
                endcase

                if ((FlushD !== 1'b1) || (FlushE !== 1'b1))
                    $fatal(1, "FAIL redirect without both flushes");
            end

            if (RegWriteW && (ResultSrcW == 2'b10)) begin
                case (dut.u_riscv_core.u_datapath.PCPlus4W)
                    32'd8: begin
                        // O JAL esta em WB enquanto seu consumidor do target
                        // esta em ID. A leitura bruta ainda nao contem o link.
                        if ((RdW !== 5'd10) || (ResultW !== 32'd8) ||
                            (dut.InstrD !== expected_program[5]) ||
                            (dut.Rs1D !== 5'd10) || (dut.RD1D !== 32'd8) ||
                            (RFRead1D === 32'd8))
                            $fatal(1, "FAIL JAL WB -> target Decode bypass");
                        saw_positive_wb_id = 1'b1;
                        $display("PASS: JAL link bypasses WB directly to target Decode");
                    end
                    32'd68: begin
                        if ((RdW !== 5'd6) || (ResultW !== 32'd68))
                            $fatal(1, "FAIL negative JAL link in WB");
                        saw_negative_link = 1'b1;
                    end
                    32'd28, 32'd44, 32'd60: begin
                        if ((RdW !== 5'd0) ||
                            (dut.RD1D !== RFRead1D) || (dut.RD2D !== RFRead2D))
                            $fatal(1, "FAIL JAL x0 created WB-Decode bypass");
                        jal_x0_wb_count = jal_x0_wb_count + 1;
                    end
                    default: $fatal(1, "FAIL unexpected JAL value in WB");
                endcase
            end

            // O consumidor imediato chegou a EX com o dado capturado em ID.
            // Nao existe produtor correspondente em M/W neste ciclo.
            if (dut.PCE == 32'd20) begin
                if ((dut.RD1E !== 32'd8) || (ForwardAE !== 2'b00) ||
                    (dut.SrcAE !== 32'd8) || (dut.ALUResultE !== 32'd9))
                    $fatal(1, "FAIL immediate JAL target consumer");
                saw_positive_consumer = 1'b1;
            end

            if (dut.PCE == 32'd80) begin
                if ((dut.SrcAE !== 32'd68) || (dut.ALUResultE !== 32'd69))
                    $fatal(1, "FAIL negative JAL link consumer");
            end

            // Confirma que o forwarding M -> EX anterior continua intacto.
            if (dut.PCE == 32'd84) begin
                if ((ForwardAE !== 2'b10) || (dut.SrcAE !== 32'd69) ||
                    (dut.ALUResultE !== 32'd70))
                    $fatal(1, "FAIL forwarding after JAL flow");
                saw_final_forwarding = 1'b1;
            end
        end

        if ((redirect_count != 5) || (jal_x0_wb_count != 3) ||
            !saw_positive_wb_id || !saw_positive_consumer ||
            !saw_negative_execute || !saw_negative_link ||
            !saw_final_forwarding)
            $fatal(1, "FAIL: not all JAL checkpoints were observed");

        if ((dut.u_riscv_core.u_datapath.u_register_file.regs[5]  !== 32'd5) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[6]  !== 32'd68) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[7]  !== 32'd7) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[8]  !== 32'd69) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[9]  !== 32'd70) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[10] !== 32'd8) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[11] !== 32'd9) ||
            (dut.RD1D !== 32'b0) || (dut.RD2D !== 32'b0))
            $fatal(1, "FAIL final architectural register values");

        $display("PASS: JAL positive/negative, x0, WB-ID bypass, flush and forwarding");
        $finish;
    end

    initial begin
        #2000;
        $fatal(1, "FAIL: JAL test timeout");
    end
endmodule
