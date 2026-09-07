`timescale 1ns/1ps

// Testa JAL pelo sistema completo: busca na IMEM, redirect em Execute,
// flush das instrucoes erradas e escrita de PC+4 pelo Writeback real.
module tb_jal;
    localparam integer PROGRAM_WORDS = 13;

    logic clk;
    logic reset;
    logic [31:0] expected_program [0:PROGRAM_WORDS-1];

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

    riscv_system_top #(
        .IMEM_INIT_FILE ("../mem/jal.hex")
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

    function automatic logic [31:0] encode_jal(
        input logic [20:0] offset,
        input logic [4:0] rd
    );
        // O imediato J espalha seus bits pela instrucao. O bit zero nao e
        // armazenado porque o deslocamento sempre representa multiplo de 2.
        encode_jal = {offset[20], offset[10:1], offset[11],
                      offset[19:12], rd, 7'b1101111};
    endfunction

    task automatic advance_cycle;
        begin
            @(posedge clk);
            #1;
            if ({StallF, StallD} !== 2'b00)
                $fatal(1, "FAIL: JAL nao deve produzir stall nesta etapa");
            if ({FlushD, FlushE} !== {2{PCSrcE}})
                $fatal(1, "FAIL: flushes nao acompanham PCSrcE");
            if ((ForwardAE === 2'b11) || (ForwardBE === 2'b11))
                $fatal(1, "FAIL: codigo 11 de forwarding foi utilizado");
            if ((dut.MemWriteM !== 1'b0) || (dut.u_data_memory.en !== 1'b0) ||
                (dut.u_data_memory.wstrb !== 4'b0000))
                $fatal(1, "FAIL: JAL ativou indevidamente a DMEM");
        end
    endtask

    // Uma instrucao do caminho errado jamais pode chegar ao WB com escrita.
    // O teste apenas le sinais internos; nao cria outro driver no RTL.
    always @(posedge clk) begin
        if (!reset && RegWriteW &&
            ((RdW == 5'd20) || (RdW == 5'd21) || (RdW == 5'd22) ||
             (RdW == 5'd23) || (RdW == 5'd24)))
            $fatal(1, "FAIL: instrucao do caminho errado tentou escrever x%0d", RdW);
    end

    initial begin
        reset = 1'b1;

        // O alvo do primeiro JAL nao usa x10 imediatamente. O forwarding atual
        // em EX/MEM encaminha ALUResultM; encaminhar PC+4 de JAL sera tratado
        // quando os produtores nao-ALU forem integrados ao forwarding completo.
        expected_program[0]  = encode_addi(12'd5,   5'd0, 5'd5);
        expected_program[1]  = encode_jal(21'd16,  5'd10);
        expected_program[2]  = encode_addi(12'd111, 5'd0, 5'd20);
        expected_program[3]  = encode_addi(12'd222, 5'd0, 5'd21);
        expected_program[4]  = encode_addi(12'd333, 5'd0, 5'd24);
        expected_program[5]  = encode_addi(12'd9,   5'd0, 5'd6);
        expected_program[6]  = encode_addi(12'd1,   5'd6, 5'd7);
        expected_program[7]  = encode_jal(21'd16,  5'd0);
        expected_program[8]  = encode_addi(12'd55,  5'd0, 5'd22);
        expected_program[9]  = encode_addi(12'd66,  5'd0, 5'd23);
        expected_program[10] = encode_addi(12'd77,  5'd0, 5'd24);
        expected_program[11] = encode_addi(12'd11,  5'd0, 5'd8);
        expected_program[12] = encode_addi(12'd1,   5'd8, 5'd9);

        #1;
        for (integer i = 0; i < PROGRAM_WORDS; i = i + 1) begin
            if (dut.u_instruction_memory.mem[i] !== expected_program[i])
                $fatal(1, "FAIL encoding word %0d: hex=%h expected=%h",
                       i, dut.u_instruction_memory.mem[i], expected_program[i]);
        end
        $display("PASS: JAL and ADDI encodings checked independently");

        // A cauda recebe NOPs apenas para permitir o esvaziamento do pipeline.
        for (integer i = PROGRAM_WORDS; i < 512; i = i + 1)
            dut.u_instruction_memory.mem[i] = 32'h0000_0013;

        advance_cycle();
        if ((dut.PCF !== 32'b0) || (dut.InstrD !== 32'b0))
            $fatal(1, "FAIL reset state");

        @(negedge clk);
        reset = 1'b0;
        if ((dut.PCF !== 32'd0) || (dut.InstrF !== expected_program[0]))
            $fatal(1, "FAIL first Fetch");

        // C1: addi x5 entra em Decode.
        advance_cycle();
        if ((dut.PCF !== 32'd4) || (dut.InstrD !== expected_program[0]))
            $fatal(1, "FAIL cycle 1");

        // C2: JAL esta em Decode e deve produzir todos os controles pedidos.
        advance_cycle();
        if ((dut.PCF !== 32'd8) || (dut.InstrD !== expected_program[1]) ||
            (dut.PCD !== 32'd4) || (dut.PCPlus4D !== 32'd8) ||
            (dut.ImmExtD !== 32'd16) ||
            (dut.u_riscv_core.RegWriteD !== 1'b1) ||
            (dut.u_riscv_core.ResultSrcD !== 2'b10) ||
            (dut.u_riscv_core.MemWriteD !== 1'b0) ||
            (dut.u_riscv_core.JumpD !== 1'b1) ||
            (dut.u_riscv_core.BranchD !== 1'b0) ||
            (dut.u_riscv_core.ImmSrcD !== 3'b011) ||
            (dut.u_riscv_core.ALUControlD !== 4'b0000) ||
            (dut.u_riscv_core.ALUSrcD !== 1'b0))
            $fatal(1, "FAIL JAL Decode controls");

        // C3: JAL chega a Execute. PCSrcE redireciona para 20 e os dois
        // registradores mais jovens sao limpos no mesmo flanco seguinte.
        advance_cycle();
        if ((PCSrcE !== 1'b1) || ({FlushD, FlushE} !== 2'b11) ||
            (dut.JumpE !== 1'b1) || (dut.PCE !== 32'd4) ||
            (dut.ImmExtE !== 32'd16) || (dut.PCTargetE !== 32'd20) ||
            (dut.ResultSrcE !== 2'b10) || (dut.RegWriteE !== 1'b1) ||
            (dut.RdE !== 5'd10))
            $fatal(1, "FAIL first JAL Execute redirect");
        $display("PASS: first JAL asserts PCSrcE, FlushD and FlushE");

        // C4: o PC aponta para o alvo e as instrucoes erradas viraram bolhas.
        advance_cycle();
        if ((dut.PCF !== 32'd20) || (dut.InstrF !== expected_program[5]) ||
            (dut.InstrD !== 32'b0) || (dut.RegWriteE !== 1'b0) ||
            (PCSrcE !== 1'b0) || ({FlushD, FlushE} !== 2'b00) ||
            (dut.u_riscv_core.u_datapath.RegWriteM !== 1'b1) ||
            (dut.u_riscv_core.u_datapath.ResultSrcM !== 2'b10) ||
            (dut.u_riscv_core.u_datapath.RdM !== 5'd10) ||
            (dut.u_riscv_core.u_datapath.PCPlus4M !== 32'd8))
            $fatal(1, "FAIL first JAL redirect/EX-MEM");

        // C5: o mux do WB seleciona PCPlus4W=8 para o link de x10.
        advance_cycle();
        if ((RegWriteW !== 1'b1) || (ResultSrcW !== 2'b10) ||
            (RdW !== 5'd10) || (ResultW !== 32'd8) ||
            (dut.u_riscv_core.u_datapath.PCPlus4W !== 32'd8))
            $fatal(1, "FAIL first JAL Writeback selection");

        // C6 escreve x10 no flanco real do Register File.
        advance_cycle();
        if (dut.u_riscv_core.u_datapath.u_register_file.regs[10] !== 32'd8)
            $fatal(1, "FAIL JAL link was not written to x10");
        $display("PASS: JAL writes PC+4 to x10 through MEM/WB");

        // C7 prova que o forwarding de uma ALU produtora continua funcionando.
        advance_cycle();
        if ((dut.PCF !== 32'd32) || (dut.InstrD !== expected_program[7]) ||
            (ForwardAE !== 2'b10) || (dut.SrcAE !== 32'd9) ||
            (dut.SrcBE !== 32'd1) || (dut.ALUResultE !== 32'd10))
            $fatal(1, "FAIL forwarding preserved before second JAL");

        // C8: JAL x0 redireciona para 44 com os mesmos flushes.
        advance_cycle();
        if ((PCSrcE !== 1'b1) || ({FlushD, FlushE} !== 2'b11) ||
            (dut.PCE !== 32'd28) || (dut.PCTargetE !== 32'd44) ||
            (dut.RdE !== 5'd0) || (dut.ResultSrcE !== 2'b10))
            $fatal(1, "FAIL JAL x0 Execute redirect");

        // C9: alvo correto; caminho errado foi novamente convertido em bolhas.
        advance_cycle();
        if ((dut.PCF !== 32'd44) || (dut.InstrF !== expected_program[11]) ||
            (dut.InstrD !== 32'b0) || (dut.RegWriteE !== 1'b0) ||
            (PCSrcE !== 1'b0))
            $fatal(1, "FAIL second JAL target/flush");

        // C10 mostra que o WB tenta escrever o link, mas com rd=x0.
        advance_cycle();
        if ((RegWriteW !== 1'b1) || (ResultSrcW !== 2'b10) ||
            (RdW !== 5'd0) || (ResultW !== 32'd32) ||
            (dut.RD1D !== 32'b0))
            $fatal(1, "FAIL JAL x0 Writeback selection");

        // C11: o Register File deve ignorar a escrita em x0. O armazenamento
        // interno de regs[0] nao precisa ser inicializado: as portas de leitura
        // e o bloqueio de forwarding definem o comportamento arquitetural de x0.
        advance_cycle();
        if ((dut.RD1E !== 32'b0) || (ForwardAE !== 2'b00))
            $fatal(1, "FAIL x0 protection after JAL x0");
        $display("PASS: JAL x0 redirects but cannot alter x0 or create forwarding");

        // C12: o ADDI do segundo alvo usa forwarding normal de x8.
        advance_cycle();
        if ((ForwardAE !== 2'b10) || (dut.SrcAE !== 32'd11) ||
            (dut.SrcBE !== 32'd1) || (dut.ALUResultE !== 32'd12))
            $fatal(1, "FAIL forwarding preserved after second JAL");

        // Esvazia os dois ultimos resultados ate o banco de registradores.
        advance_cycle();
        advance_cycle();
        advance_cycle();

        if ((dut.u_riscv_core.u_datapath.u_register_file.regs[5]  !== 32'd5) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[6]  !== 32'd9) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[7]  !== 32'd10) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[8]  !== 32'd11) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[9]  !== 32'd12) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[10] !== 32'd8) ||
            (dut.RD1D !== 32'b0) || (dut.RD2D !== 32'b0))
            $fatal(1, "FAIL final architectural register values");

        $display("PASS: forward JAL, JAL x0, wrong-path flush and existing forwarding");
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "FAIL: JAL test timeout");
    end
endmodule
