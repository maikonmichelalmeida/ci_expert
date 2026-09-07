`timescale 1ns/1ps

// Verifica separadamente o mux WB -> Decode. O programa posiciona cada
// consumidor em ID exatamente quando seu produtor aparece em WB.
module tb_wb_decode;
    localparam integer PROGRAM_WORDS = 60;

    logic clk;
    logic reset;
    logic [31:0] expected_program [0:PROGRAM_WORDS-1];

    wire [31:0] RFRead1D  = dut.u_riscv_core.u_datapath.RFRead1D;
    wire [31:0] RFRead2D  = dut.u_riscv_core.u_datapath.RFRead2D;
    wire [31:0] RD1D      = dut.RD1D;
    wire [31:0] RD2D      = dut.RD2D;
    wire        RegWriteW = dut.u_riscv_core.u_datapath.RegWriteW;
    wire [4:0]  RdW       = dut.u_riscv_core.u_datapath.RdW;
    wire [31:0] ResultW    = dut.u_riscv_core.u_datapath.ResultW;

    riscv_system_top #(
        .IMEM_INIT_FILE ("../mem/wb_decode.hex")
    ) dut (
        .clk   (clk),
        .reset (reset)
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

    function automatic logic [31:0] encode_add(
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [4:0] rd
    );
        encode_add = {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011};
    endfunction

    task automatic check_common;
        begin
            if ({dut.u_riscv_core.StallF, dut.u_riscv_core.StallD,
                 dut.u_riscv_core.FlushD, dut.u_riscv_core.FlushE} !== 4'b0000)
                $fatal(1, "FAIL: stall/flush inesperado no teste WB-Decode");
            if ((dut.u_riscv_core.ForwardAE === 2'b11) ||
                (dut.u_riscv_core.ForwardBE === 2'b11))
                $fatal(1, "FAIL: forwarding produziu o codigo reservado 11");
            if ((dut.MemWriteM !== 1'b0) || (dut.u_data_memory.en !== 1'b0))
                $fatal(1, "FAIL: acesso inesperado a DMEM");
        end
    endtask

    initial begin
        reset = 1'b1;

        for (integer i = 0; i < PROGRAM_WORDS; i = i + 1)
            expected_program[i] = encode_addi(12'd0, 5'd0, 5'd0);

        expected_program[0]  = encode_addi(12'd10, 5'd0, 5'd5);
        expected_program[1]  = encode_addi(12'd1,  5'd0, 5'd20);
        expected_program[2]  = encode_addi(12'd2,  5'd0, 5'd21);
        expected_program[3]  = encode_add(5'd0, 5'd5, 5'd6);

        expected_program[8]  = encode_addi(12'd20, 5'd0, 5'd7);
        expected_program[9]  = encode_addi(12'd1,  5'd0, 5'd22);
        expected_program[10] = encode_addi(12'd2,  5'd0, 5'd23);
        expected_program[11] = encode_add(5'd7, 5'd0, 5'd8);

        expected_program[16] = encode_addi(12'd3, 5'd0, 5'd9);
        expected_program[17] = encode_addi(12'd1, 5'd0, 5'd24);
        expected_program[18] = encode_addi(12'd2, 5'd0, 5'd25);
        expected_program[19] = encode_add(5'd9, 5'd9, 5'd10);

        expected_program[24] = encode_addi(12'd30, 5'd0, 5'd11);
        expected_program[25] = encode_addi(12'd1,  5'd0, 5'd26);
        expected_program[26] = encode_addi(12'd2,  5'd0, 5'd27);
        expected_program[27] = encode_add(5'd7, 5'd5, 5'd12);

        // Opcode invalido com RdD=5: chega a W com RdW=5, mas RegWriteW=0.
        expected_program[32] = 32'h0000_0280;
        expected_program[35] = encode_add(5'd7, 5'd5, 5'd13);

        expected_program[40] = encode_addi(12'd123, 5'd0, 5'd0);
        expected_program[43] = encode_add(5'd0, 5'd0, 5'd14);

        expected_program[48] = encode_addi(12'd44, 5'd0, 5'd15);
        expected_program[56] = encode_addi(12'd99, 5'd0, 5'd15);
        expected_program[59] = encode_add(5'd0, 5'd15, 5'd16);

        #1;
        for (integer i = 0; i < PROGRAM_WORDS; i = i + 1) begin
            if (dut.u_instruction_memory.mem[i] !== expected_program[i])
                $fatal(1, "FAIL encoding word %0d: hex=%h expected=%h",
                       i, dut.u_instruction_memory.mem[i], expected_program[i]);
        end
        for (integer i = PROGRAM_WORDS; i < 512; i = i + 1)
            dut.u_instruction_memory.mem[i] = 32'h0000_0013;
        $display("PASS: WB-Decode program encodings checked independently");

        @(posedge clk);
        #1;
        if ((RegWriteW !== 1'b0) || (dut.RD1D !== 32'b0) ||
            (dut.RD2D !== 32'b0))
            $fatal(1, "FAIL: reset must keep bypass inactive");

        @(negedge clk);
        reset = 1'b0;

        for (integer cycle = 1; cycle <= PROGRAM_WORDS; cycle = cycle + 1) begin
            @(posedge clk);
            #1;
            check_common();

            case (cycle)
                4: begin
                    if ((RegWriteW !== 1'b1) || (RdW !== 5'd5) ||
                        (ResultW !== 32'd10) || (dut.Rs1D !== 5'd5) ||
                        (RD1D !== 32'd10) || (RD2D !== RFRead2D) ||
                        (RFRead1D === 32'd10))
                        $fatal(1, "FAIL: bypass WB->rs1 em Decode");
                    $display("PASS: rs1 recebe ResultW enquanto a leitura bruta ainda e antiga");
                end
                5: begin
                    if ((dut.PCE !== 32'd12) || (dut.RD1E !== 32'd10) ||
                        (dut.u_riscv_core.ForwardAE !== 2'b00) ||
                        (dut.ALUResultE !== 32'd10))
                        $fatal(1, "FAIL: consumidor rs1 nao recebeu bypass no ID/EX");
                end
                12: begin
                    if ((RegWriteW !== 1'b1) || (RdW !== 5'd7) ||
                        (ResultW !== 32'd20) || (dut.Rs2D !== 5'd7) ||
                        (RD2D !== 32'd20) || (RD1D !== RFRead1D) ||
                        (RFRead2D === 32'd20))
                        $fatal(1, "FAIL: bypass WB->rs2 em Decode");
                    $display("PASS: rs2 recebe ResultW pelo bypass WB-Decode");
                end
                13: begin
                    if ((dut.PCE !== 32'd44) || (dut.RD2E !== 32'd20) ||
                        (dut.u_riscv_core.ForwardBE !== 2'b00) ||
                        (dut.ALUResultE !== 32'd20))
                        $fatal(1, "FAIL: consumidor rs2 nao recebeu bypass no ID/EX");
                end
                20: begin
                    if ((RegWriteW !== 1'b1) || (RdW !== 5'd9) ||
                        (ResultW !== 32'd3) || (dut.Rs1D !== 5'd9) ||
                        (dut.Rs2D !== 5'd9) || (RD1D !== 32'd3) ||
                        (RD2D !== 32'd3))
                        $fatal(1, "FAIL: bypass simultaneo para rs1 e rs2");
                    $display("PASS: match simultaneo alimenta RD1D e RD2D");
                end
                21: begin
                    if ((dut.PCE !== 32'd76) || (dut.ALUResultE !== 32'd6))
                        $fatal(1, "FAIL: consumidor dos dois operandos");
                end
                28: begin
                    if ((RegWriteW !== 1'b1) || (RdW !== 5'd11) ||
                        (dut.Rs1D !== 5'd5) || (dut.Rs2D !== 5'd7) ||
                        (RD1D !== RFRead1D) || (RD2D !== RFRead2D) ||
                        (RD1D !== 32'd10) || (RD2D !== 32'd20))
                        $fatal(1, "FAIL: bypass ocorreu sem match");
                    $display("PASS: sem match preserva as duas leituras brutas");
                end
                36: begin
                    if ((RegWriteW !== 1'b0) || (RdW !== 5'd5) ||
                        (dut.Rs1D !== 5'd5) || (RD1D !== RFRead1D) ||
                        (RD2D !== RFRead2D))
                        $fatal(1, "FAIL: RegWriteW=0 permitiu bypass");
                    $display("PASS: RegWriteW=0 bloqueia o bypass mesmo com match");
                end
                44: begin
                    if ((RegWriteW !== 1'b1) || (RdW !== 5'd0) ||
                        (ResultW !== 32'd123) || (dut.Rs1D !== 5'd0) ||
                        (dut.Rs2D !== 5'd0) || (RD1D !== RFRead1D) ||
                        (RD2D !== RFRead2D) || (RD1D !== 32'b0))
                        $fatal(1, "FAIL: RdW=x0 criou bypass");
                    $display("PASS: RdW=x0 nao cria dependencia de bypass");
                end
                60: begin
                    if ((RegWriteW !== 1'b1) || (RdW !== 5'd15) ||
                        (ResultW !== 32'd99) || (dut.Rs1D !== 5'd15) ||
                        (RFRead1D !== 32'd44) || (RD1D !== 32'd99))
                        $fatal(1, "FAIL: preparacao do teste de reset");

                    // Reset e combinado no mux de bypass. Antes do proximo
                    // posedge ele ja deve revelar novamente a leitura bruta 44.
                    reset = 1'b1;
                    #1;
                    if ((RFRead1D !== 32'd44) || (RD1D !== 32'd44))
                        $fatal(1, "FAIL: reset nao desabilitou bypass pendente");
                    $display("PASS: reset desabilita bypass pendente");
                end
                default: begin
                end
            endcase
        end

        if ((dut.u_riscv_core.u_datapath.u_register_file.regs[6]  !== 32'd10) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[8]  !== 32'd20) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[10] !== 32'd6) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[12] !== 32'd30) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[13] !== 32'd30) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[15] !== 32'd44))
            $fatal(1, "FAIL: resultados arquiteturais do bypass");

        @(posedge clk);
        #1;
        if ((RegWriteW !== 1'b0) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[15] !== 32'd44))
            $fatal(1, "FAIL: reset permitiu a escrita pendente de x15");

        $display("PASS: bypass WB-Decode completo sem alterar o Register File");
        $finish;
    end

    initial begin
        #2000;
        $fatal(1, "FAIL: WB-Decode test timeout");
    end
endmodule
