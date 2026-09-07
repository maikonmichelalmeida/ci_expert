`timescale 1ns/1ps

// Programa real na IMEM: addi x1,x0,1 seguido apenas de NOPs.
// As observacoes por hierarquia dispensam portas de debug no processador.
module tb_riscv_system_top;

    logic clk;
    logic reset;
    integer useful_writes;
    integer x0_writes;

    // Apelidos locais do TESTBENCH para facilitar a leitura dos checks de WB.
    wire        RegWriteW  = dut.u_riscv_core.u_datapath.RegWriteW;
    wire [4:0]  RdW        = dut.u_riscv_core.u_datapath.RdW;
    wire [31:0] ResultW    = dut.u_riscv_core.u_datapath.ResultW;
    wire [31:0] ALUResultW = dut.u_riscv_core.u_datapath.ALUResultW;
    wire [1:0]  ResultSrcW = dut.u_riscv_core.u_datapath.ResultSrcW;
    wire [31:0] PCPlus4W   = dut.u_riscv_core.u_datapath.PCPlus4W;
    wire [31:0] x1         = dut.u_riscv_core.u_datapath.u_register_file.regs[1];

    riscv_system_top #(
        .IMEM_INIT_FILE ("../mem/program.hex")
    ) dut (
        .clk   (clk),
        .reset (reset)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

`ifndef VERILATOR
`ifndef __ICARUS__
    initial begin
        $fsdbDumpfile("test.fsdb");
        $fsdbDumpvars(0, tb_riscv_system_top);
        $fsdbDumpMDA(0, tb_riscv_system_top);
    end
`endif
`endif

    // Observa o comando que o banco recebe ANTES das atualizacoes NBA.
    // As assertions do conteudo do banco, abaixo, esperam #1 depois do clock.
    always @(posedge clk) begin
        if (!reset) begin
            if ((RegWriteW !== 1'b0) && (RegWriteW !== 1'b1))
                $fatal(1, "FAIL: unknown Writeback enable");
            if (RegWriteW) begin
                if (RdW == 5'd0) begin
                    x0_writes <= x0_writes + 1;
                    if (ResultW !== 32'b0)
                        $fatal(1, "FAIL: NOP should produce zero");
                end else begin
                    if ((RdW !== 5'd1) || (ResultW !== 32'd1))
                        $fatal(1, "FAIL: unexpected register write rd=%d data=%h", RdW, ResultW);
                    useful_writes <= useful_writes + 1;
                end
            end
        end
        #1;
        if ({dut.u_riscv_core.StallF, dut.u_riscv_core.StallD,
             dut.u_riscv_core.FlushD, dut.u_riscv_core.FlushE,
             dut.u_riscv_core.ForwardAE, dut.u_riscv_core.ForwardBE} !== 8'b0)
            $fatal(1, "FAIL: hazard_unit must remain neutral");
        if ((dut.u_riscv_core.PCSrcE !== 1'b0) || (dut.MemWriteM !== 1'b0) ||
            (dut.u_data_memory.en !== 1'b0) || (dut.u_data_memory.wstrb !== 4'b0))
            $fatal(1, "FAIL: branch or data memory access enabled");
        if (reset && (dut.u_riscv_core.u_datapath.u_register_file.rd_we !== 1'b0))
            $fatal(1, "FAIL: reset allowed a register write");
    end

    task automatic check_reset;
        begin
            if ({dut.u_riscv_core.u_datapath.RegWriteM,
                 dut.u_riscv_core.u_datapath.ResultSrcM, dut.MemWriteM,
                 dut.ALUResultM, dut.WriteDataM, dut.u_riscv_core.u_datapath.RdM,
                 dut.u_riscv_core.u_datapath.PCPlus4M} !== 105'b0)
                $fatal(1, "FAIL: EX/MEM reset");
            if ({RegWriteW, ResultSrcW, ALUResultW,
                 dut.u_riscv_core.u_datapath.ReadDataW, RdW, PCPlus4W} !== 104'b0)
                $fatal(1, "FAIL: MEM/WB reset");
            if ({dut.u_riscv_core.RegWriteD, dut.u_riscv_core.ResultSrcD,
                 dut.u_riscv_core.MemWriteD, dut.u_riscv_core.JumpD,
                 dut.u_riscv_core.BranchD, dut.u_riscv_core.ALUControlD,
                 dut.u_riscv_core.ALUSrcD, dut.u_riscv_core.ImmSrcD} !== 14'b0)
                $fatal(1, "FAIL: reset control defaults");
            $display("PASS: safe reset in EX/MEM, MEM/WB and control_unit");
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
            if ((dut.PCF      !== expected_pcf) ||
                (dut.PCPlus4F !== (expected_pcf + 32'd4)) ||
                (dut.InstrF   !== expected_instrf) ||
                (dut.InstrD   !== expected_instrd) ||
                (dut.PCD      !== expected_pcd) ||
                (dut.PCPlus4D !== expected_pcplus4d))
                $fatal(1, "FAIL Fetch: PCF=%h InstrF=%h InstrD=%h PCD=%h PCPlus4D=%h",
                       dut.PCF, dut.InstrF, dut.InstrD, dut.PCD, dut.PCPlus4D);
            $display("PASS Fetch: PCF=%0d InstrD=%h PCD=%0d", dut.PCF, dut.InstrD, dut.PCD);
        end
    endtask

    task automatic check_addi_until_wb;
        begin
            // InstrF aponta para ADDI antes do primeiro clock fora do reset.
            check_fetch(32'd0, 32'h0010_0093, 32'b0, 32'b0, 32'b0);
            @(posedge clk);
            #1;
            check_fetch(32'd4, 32'h0000_0013, 32'h0010_0093, 32'd0, 32'd4);
            if ((dut.OpD !== 7'b0010011) || (dut.Rs1D !== 5'd0) ||
                (dut.RdD !== 5'd1) || (dut.Funct3D !== 3'b000) ||
                (dut.RD1D !== 32'b0) || (dut.ImmExtD !== 32'd1))
                $fatal(1, "FAIL: ADDI fields, x0 read or I immediate");
            if ((dut.u_riscv_core.RegWriteD !== 1'b1) ||
                (dut.u_riscv_core.ALUSrcD !== 1'b1) ||
                (dut.u_riscv_core.ALUControlD !== 4'b0000) ||
                (dut.u_riscv_core.ImmSrcD !== 3'b000) ||
                (dut.u_riscv_core.ResultSrcD !== 2'b00))
                $fatal(1, "FAIL: ADDI control signals");
            $display("PASS: ADDI Decode and ImmExtD=1");

            @(posedge clk);
            #1;
            check_fetch(32'd8, 32'h0000_0013, 32'h0000_0013, 32'd4, 32'd8);
            if ((dut.RD1E !== 32'b0) || (dut.ImmExtE !== 32'd1) ||
                (dut.PCE !== 32'd0) || (dut.PCPlus4E !== 32'd4) ||
                (dut.RdE !== 5'd1) || (dut.RegWriteE !== 1'b1) ||
                (dut.ALUSrcE !== 1'b1) || (dut.ALUControlE !== 4'b0000) ||
                (dut.SrcAE !== 32'd0) || (dut.SrcBE !== 32'd1) ||
                (dut.ALUResultE !== 32'd1) || (dut.ZeroE !== 1'b0))
                $fatal(1, "FAIL: ADDI ID/EX or Execute");
            $display("PASS: ADDI Execute 0 + 1 = 1");

            @(posedge clk);
            #1;
            check_fetch(32'd12, 32'h0000_0013, 32'h0000_0013, 32'd8, 32'd12);
            if ((dut.ALUResultM !== 32'd1) ||
                (dut.u_riscv_core.u_datapath.RdM !== 5'd1) ||
                (dut.u_riscv_core.u_datapath.RegWriteM !== 1'b1) ||
                (dut.u_riscv_core.u_datapath.ResultSrcM !== 2'b00) ||
                (dut.u_riscv_core.u_datapath.PCPlus4M !== 32'd4))
                $fatal(1, "FAIL: ADDI EX/MEM");
            $display("PASS: ADDI MEM ALUResultM=1 RdM=1");

            @(posedge clk);
            #1;
            if ((ALUResultW !== 32'd1) || (RdW !== 5'd1) ||
                (RegWriteW !== 1'b1) || (ResultSrcW !== 2'b00) ||
                (PCPlus4W !== 32'd4) || (ResultW !== 32'd1))
                $fatal(1, "FAIL: ADDI MEM/WB or Writeback mux");
            if ((dut.u_riscv_core.u_datapath.u_register_file.rd_addr !== 5'd1) ||
                (dut.u_riscv_core.u_datapath.u_register_file.rd_data !== 32'd1) ||
                (dut.u_riscv_core.u_datapath.u_register_file.rd_we !== 1'b1))
                $fatal(1, "FAIL: WB connection to Register File");
            // O WB acabou de receber ADDI; o banco so grava no proximo clock.
            if (x1 !== 32'hdead_beef)
                $fatal(1, "FAIL: x1 changed before the WB write edge");
            $display("PASS: ADDI WB ResultW=1 RdW=1 RegWriteW=1");
        end
    endtask

    initial begin
        reset = 1'b1;
        useful_writes = 0;
        x0_writes = 0;
        #1;
        // Apenas verificacao: valor sentinela para detectar escrita antecipada.
        // O programa e quem deve substituir este valor por 1, via WB real.
        dut.u_riscv_core.u_datapath.u_register_file.regs[1] = 32'hdead_beef;
        // Depois das seis palavras do arquivo, mantem somente NOPs na simulacao.
        for (integer i = 6; i < 512; i = i + 1)
            dut.u_instruction_memory.mem[i] = 32'h0000_0013;

        @(posedge clk);
        #1;
        check_reset();
        @(negedge clk);
        reset = 1'b0;
        #1;
        check_addi_until_wb();

        // Reset com ADDI pendente em W deve cancelar essa escrita.
        @(negedge clk);
        reset = 1'b1;
        #1;
        if (dut.u_riscv_core.u_datapath.u_register_file.rd_we !== 1'b0)
            $fatal(1, "FAIL: reset did not block pending WB");
        @(posedge clk);
        #1;
        check_reset();
        if ((x1 !== 32'hdead_beef) || (useful_writes != 0))
            $fatal(1, "FAIL: pending ADDI wrote during reset");
        $display("PASS: reset cancels pending WB without clearing the Register File");

        // Agora deixa a mesma instrucao completar todas as fronteiras e gravar.
        @(negedge clk);
        reset = 1'b0;
        #1;
        check_addi_until_wb();
        @(posedge clk);
        #1;
        if ((x1 !== 32'h0000_0001) || (useful_writes != 1))
            $fatal(1, "FAIL: ADDI did not write x1=1 through WB: x1=%h", x1);
        $display("PASS: end-to-end ADDI wrote x1=00000001 through real WB");

        // Os cinco NOPs tambem chegam ao WB; x0 continua lido como zero.
        repeat (5) begin
            @(posedge clk);
            #1;
            if ((dut.RD1D !== 32'b0) || (dut.RD2D !== 32'b0) || (x1 !== 32'd1))
                $fatal(1, "FAIL: NOP changed architectural data");
        end
        if ((useful_writes != 1) || (x0_writes != 5))
            $fatal(1, "FAIL: expected one x1 write and five ignored x0 writes");
        $display("PASS: five NOPs preserve x0=0 and x1=1; hazard_unit remains neutral");
        $display("PASS: all system/end-to-end tests completed");
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "FAIL: system test timeout");
    end

endmodule
