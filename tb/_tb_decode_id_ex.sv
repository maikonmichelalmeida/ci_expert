`timescale 1ns/1ps

// Teste estrutural do Decode e do registrador ID/EX.
// Ele instancia o datapath diretamente para poder aplicar controles D nao
// nulos, inclusive combinacoes que o decoder de OP-IMM nao produz.
module tb_decode_id_ex;

    localparam logic [2:0] IMM_I        = 3'b000;
    localparam logic [2:0] IMM_S        = 3'b001;
    localparam logic [2:0] IMM_B        = 3'b010;
    localparam logic [2:0] IMM_J        = 3'b011;
    localparam logic [2:0] IMM_U        = 3'b100;
    localparam logic [2:0] IMM_RESERVED = 3'b101;

    logic clk;
    logic reset;
    logic [31:0] InstrF;

    logic       RegWriteD;
    logic [1:0] ResultSrcD;
    logic       MemWriteD;
    logic [2:0] StoreControlD;
    logic       JumpD;
    logic       JalrD;
    logic       BranchD;
    logic [2:0] BranchControlD;
    logic [3:0] ALUControlD;
    logic       ALUSrcD;
    logic       ALUASrcD;
    logic [2:0] ImmSrcD;

    logic       StallF;
    logic       StallD;
    logic       FlushD;
    logic       FlushE;
    logic [1:0] ForwardAE;
    logic [1:0] ForwardBE;

    logic [31:0] ReadDataM;

    logic [31:0] PCF;
    logic [31:0] PCPlus4F;
    logic [31:0] InstrD;
    logic [31:0] PCD;
    logic [31:0] PCPlus4D;
    logic [6:0]  OpD;
    logic [4:0]  RdD;
    logic [2:0]  Funct3D;
    logic [4:0]  Rs1D;
    logic [4:0]  Rs2D;
    logic        Funct7b5D;
    logic [31:0] RD1D;
    logic [31:0] RD2D;
    logic [31:0] ImmExtD;

    logic [31:0] RD1E;
    logic [31:0] RD2E;
    logic [31:0] PCE;
    logic [4:0]  Rs1E;
    logic [4:0]  Rs2E;
    logic [4:0]  RdE;
    logic [31:0] ImmExtE;
    logic [31:0] PCPlus4E;
    logic        RegWriteE;
    logic [1:0]  ResultSrcE;
    logic        MemWriteE;
    logic [2:0]  StoreControlE;
    logic        JumpE;
    logic        JalrE;
    logic        BranchE;
    logic [3:0]  ALUControlE;
    logic        ALUSrcE;
    logic        ALUASrcE;
    logic [31:0] SrcAE;
    logic [31:0] ALUOperandAE;
    logic [31:0] WriteDataE;
    logic [31:0] SrcBE;
    logic [31:0] ALUResultE;
    logic        ZeroE;
    logic [31:0] PCTargetE;
    logic [2:0]  StoreControlM;

    datapath dut (
        .clk          (clk),
        .reset        (reset),
        .ReadDataM    (ReadDataM),
        .ALUResultM   (),
        .WriteDataM   (),
        .MemWriteM    (),
        .StoreControlM(StoreControlM),
        .RegWriteM    (),
        .RdM          (),
        .RegWriteW    (),
        .RdW          (),
        .InstrF       (InstrF),
        .RegWriteD    (RegWriteD),
        .ResultSrcD   (ResultSrcD),
        .MemWriteD    (MemWriteD),
        .StoreControlD(StoreControlD),
        .JumpD        (JumpD),
        .JalrD        (JalrD),
        .BranchD      (BranchD),
        .BranchControlD(BranchControlD),
        .ALUControlD  (ALUControlD),
        .ALUSrcD      (ALUSrcD),
        .ALUASrcD     (ALUASrcD),
        .ImmSrcD      (ImmSrcD),
        .StallF       (StallF),
        .StallD       (StallD),
        .FlushD       (FlushD),
        .FlushE       (FlushE),
        .ForwardAE    (ForwardAE),
        .ForwardBE    (ForwardBE),
        .PCSrcE       (),
        .PCTargetE    (PCTargetE),
        .PCF          (PCF),
        .PCPlus4F     (PCPlus4F),
        .InstrD       (InstrD),
        .PCD          (PCD),
        .PCPlus4D     (PCPlus4D),
        .OpD          (OpD),
        .RdD          (RdD),
        .Funct3D      (Funct3D),
        .Rs1D         (Rs1D),
        .Rs2D         (Rs2D),
        .Funct7b5D    (Funct7b5D),
        .RD1D         (RD1D),
        .RD2D         (RD2D),
        .ImmExtD      (ImmExtD),
        .RD1E         (RD1E),
        .RD2E         (RD2E),
        .PCE          (PCE),
        .Rs1E         (Rs1E),
        .Rs2E         (Rs2E),
        .RdE          (RdE),
        .ImmExtE      (ImmExtE),
        .PCPlus4E     (PCPlus4E),
        .RegWriteE    (RegWriteE),
        .ResultSrcE   (ResultSrcE),
        .MemWriteE    (MemWriteE),
        .StoreControlE(StoreControlE),
        .JumpE        (JumpE),
        .JalrE        (JalrE),
        .BranchE      (BranchE),
        .ALUControlE  (ALUControlE),
        .ALUSrcE      (ALUSrcE),
        .ALUASrcE     (ALUASrcE),
        .SrcAE        (SrcAE),
        .ALUOperandAE (ALUOperandAE),
        .WriteDataE   (WriteDataE),
        .SrcBE        (SrcBE),
        .ALUResultE   (ALUResultE),
        .ZeroE        (ZeroE)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic prepare_register (
        input logic [4:0]  address,
        input logic [31:0] instruction,
        input logic [2:0]  immediate_source,
        input logic [3:0]  alu_control,
        input logic [31:0] expected_data
    );
        begin
            // O valor entra pelo caminho real D -> E -> M -> W. Assim o teste
            // nao cria um segundo driver sobre regs[], que pertence ao always_ff
            // do Register File.
            @(negedge clk);
            reset       = 1'b0;
            FlushD      = 1'b0;
            FlushE      = 1'b0;
            StallD      = 1'b0;
            InstrF      = instruction;
            RegWriteD   = 1'b0;
            ResultSrcD  = 2'b00;
            MemWriteD   = 1'b0;
            StoreControlD = 3'b000;
            JumpD       = 1'b0;
            JalrD       = 1'b0;
            BranchD     = 1'b0;
            ALUControlD = 4'b0000;
            ALUSrcD     = 1'b0;
            ALUASrcD    = 1'b0;
            ImmSrcD     = immediate_source;
            @(posedge clk);
            #1;

            @(negedge clk);
            RegWriteD   = 1'b1;
            ALUControlD = alu_control;
            ALUSrcD     = 1'b1;
            @(posedge clk);
            #1;

            @(negedge clk);
            InstrF      = 32'b0;
            RegWriteD   = 1'b0;
            ALUControlD = 4'b0000;
            ALUSrcD     = 1'b0;
            ImmSrcD     = IMM_I;
            repeat (3) @(posedge clk);
            #1;
            if (dut.u_register_file.regs[address] !== expected_data)
                $fatal(1, "FAIL prepare x%0d: value=%h expected=%h",
                       address, dut.u_register_file.regs[address], expected_data);
        end
    endtask

    task automatic check_late_pipeline_transfer;
        logic [107:0] expected_m;
        logic [103:0] expected_w;
        begin
            @(negedge clk);
            // Fotografias das entradas ANTES do clock; depois do clock o
            // estagio anterior ja pode conter outra instrucao.
            expected_m = {RegWriteE, ResultSrcE, MemWriteE, StoreControlE,
                          ALUResultE,
                          WriteDataE, RdE, PCPlus4E};
            expected_w = {dut.RegWriteM, dut.ResultSrcM, dut.ALUResultM,
                          ReadDataM, dut.RdM, dut.PCPlus4M};
            @(posedge clk);
            #1;
            if ({dut.RegWriteM, dut.ResultSrcM, dut.MemWriteM, StoreControlM,
                 dut.ALUResultM,
                 dut.WriteDataM, dut.RdM, dut.PCPlus4M} !== expected_m)
                $fatal(1, "FAIL EX/MEM: fields did not travel together");
            if ({dut.RegWriteW, dut.ResultSrcW, dut.ALUResultW, dut.ReadDataW,
                 dut.RdW, dut.PCPlus4W} !== expected_w)
                $fatal(1, "FAIL MEM/WB: fields did not travel together");
            $display("PASS: EX/MEM and MEM/WB transport all fields");
        end
    endtask

    task automatic check_late_pipeline_reset;
        begin
            if ({dut.RegWriteM, dut.ResultSrcM, dut.MemWriteM, StoreControlM,
                 dut.ALUResultM, dut.WriteDataM, dut.RdM,
                 dut.PCPlus4M} !== 108'b0)
                $fatal(1, "FAIL reset: EX/MEM was not cleared");
            if ({dut.RegWriteW, dut.ResultSrcW, dut.ALUResultW, dut.ReadDataW,
                 dut.RdW, dut.PCPlus4W} !== 104'b0)
                $fatal(1, "FAIL reset: MEM/WB was not cleared");
            $display("PASS: reset clears all EX/MEM and MEM/WB fields");
        end
    endtask

    task automatic check_wb_mux (
        input logic [1:0] source,
        input logic [31:0] expected
    );
        begin
            @(negedge clk);
            ResultSrcD = source;
            // D -> E -> M -> W. RegWriteD=0: este teste so observa o mux.
            repeat (3) @(posedge clk);
            #1;
            if ((dut.ResultSrcW !== source) || (dut.ResultW !== expected))
                $fatal(1, "FAIL WB mux: source=%b result=%h expected=%h",
                       source, dut.ResultW, expected);
            $display("PASS: structural WB mux source=%b result=%h", source, expected);
        end
    endtask

    task automatic check_immediate (
        input logic [31:0] instruction,
        input logic [2:0]  immediate_source,
        input logic [31:0] expected,
        input string       test_name
    );
        begin
            @(negedge clk);
            InstrF  = instruction;
            ImmSrcD = immediate_source;
            StallD  = 1'b0;
            FlushD  = 1'b0;
            @(posedge clk);
            #1;
            if (ImmExtD !== expected) begin
                $fatal(1, "FAIL %s: InstrD=%h ImmExtD=%h expected=%h",
                       test_name, InstrD, ImmExtD, expected);
            end
            $display("PASS: %s immediate = %h", test_name, ImmExtD);
        end
    endtask

    task automatic check_id_ex_transfer;
        begin
            #1;
            if ((RD1E        !== RD1D)       ||
                (RD2E        !== RD2D)       ||
                (PCE         !== PCD)        ||
                (Rs1E        !== Rs1D)       ||
                (Rs2E        !== Rs2D)       ||
                (RdE         !== RdD)        ||
                (ImmExtE     !== ImmExtD)    ||
                (PCPlus4E    !== PCPlus4D)   ||
                (RegWriteE   !== RegWriteD)  ||
                (ResultSrcE  !== ResultSrcD) ||
                (MemWriteE   !== MemWriteD)  ||
                (StoreControlE !== StoreControlD) ||
                (JumpE       !== JumpD)      ||
                (JalrE       !== JalrD)      ||
                (BranchE     !== BranchD)    ||
                (dut.BranchControlE !== BranchControlD) ||
                (ALUControlE !== ALUControlD)||
                (ALUSrcE     !== ALUSrcD)    ||
                (ALUASrcE    !== ALUASrcD)) begin
                $fatal(1, "FAIL ID/EX: a signal was not transported from D to E");
            end
            $display("PASS: ID/EX transports data and control signals from D to E");
        end
    endtask

    task automatic check_id_ex_clear;
        begin
            #1;
            if ((RD1E        !== 32'b0) || (RD2E       !== 32'b0) ||
                (PCE         !== 32'b0) || (Rs1E       !== 5'b0)  ||
                (Rs2E        !== 5'b0)  || (RdE        !== 5'b0)  ||
                (ImmExtE     !== 32'b0) || (PCPlus4E   !== 32'b0) ||
                (RegWriteE   !== 1'b0)  || (ResultSrcE !== 2'b00) ||
                (MemWriteE   !== 1'b0)  || (JumpE      !== 1'b0)  ||
                (StoreControlE !== 3'b000) ||
                (JalrE       !== 1'b0)  ||
                (BranchE     !== 1'b0)  || (dut.BranchControlE !== 3'b000) ||
                (ALUControlE !== 4'b0000) ||
                (ALUSrcE     !== 1'b0) || (ALUASrcE !== 1'b0)) begin
                $fatal(1, "FAIL FlushE: ID/EX was not cleared");
            end
            $display("PASS: FlushE clears every ID/EX data and control field");
        end
    endtask

    task automatic check_execute (
        input logic [31:0] expected_src_a,
        input logic [31:0] expected_write_data,
        input logic [31:0] expected_src_b,
        input logic [31:0] expected_result,
        input logic        expected_zero,
        input string       test_name
    );
        begin
            #1;
            if ((SrcAE      !== expected_src_a)      ||
                (WriteDataE !== expected_write_data) ||
                (SrcBE      !== expected_src_b)      ||
                (ALUResultE !== expected_result)     ||
                (ZeroE      !== expected_zero)) begin
                $fatal(1,
                    "FAIL %s: SrcAE=%h WriteDataE=%h SrcBE=%h ALUResultE=%h ZeroE=%b",
                    test_name, SrcAE, WriteDataE, SrcBE, ALUResultE, ZeroE);
            end
            $display("PASS: %s", test_name);
        end
    endtask

    initial begin
        reset       = 1'b1;
        InstrF      = 32'b0;
        RegWriteD   = 1'b0;
        ResultSrcD  = 2'b00;
        MemWriteD   = 1'b0;
        StoreControlD = 3'b000;
        JumpD       = 1'b0;
        JalrD       = 1'b0;
        BranchD     = 1'b0;
        BranchControlD = 3'b000;
        ALUControlD = 4'b0000;
        ALUSrcD     = 1'b0;
        ALUASrcD    = 1'b0;
        ImmSrcD     = IMM_I;
        StallF      = 1'b0;
        StallD      = 1'b0;
        FlushD      = 1'b0;
        FlushE      = 1'b0;
        ForwardAE   = 2'b00;
        ForwardBE   = 2'b00;
        ReadDataM   = 32'h1234_5678;

        repeat (2) @(posedge clk);
        #1;
        check_late_pipeline_reset();

        @(negedge clk);
        reset = 1'b0;

        // Prepara x1/x2 pelo Writeback real. LUI facilita criar padroes visuais
        // sem qualquer escrita hierarquica concorrente no Register File.
        prepare_register(5'd1, 32'h1111_10b7, IMM_U, 4'b1010,
                         32'h1111_1000);
        prepare_register(5'd2, 32'h2222_2137, IMM_U, 4'b1010,
                         32'h2222_2000);

        // Cada instrucao abaixo exercita uma montagem diferente do Extend.
        check_immediate(32'hfff0_0093, IMM_I, 32'hffff_ffff, "I format -1");
        check_immediate(32'hfe20_ae23, IMM_S, 32'hffff_fffc, "S format -4");
        check_immediate(32'h7e00_0fa3, IMM_S, 32'h0000_07ff,
                        "S format +2047");
        check_immediate(32'h8000_2023, IMM_S, 32'hffff_f800,
                        "S format -2048");
        check_immediate(32'h0000_0463, IMM_B, 32'h0000_0008, "B format +8");
        check_immediate(32'h0100_006f, IMM_J, 32'h0000_0010, "J format +16");
        check_immediate(32'h0000_00b7, IMM_U, 32'h0000_0000, "U format 00000");
        check_immediate(32'h0000_10b7, IMM_U, 32'h0000_1000, "U format 00001");
        check_immediate(32'h7fff_f0b7, IMM_U, 32'h7fff_f000, "U format 7ffff");
        check_immediate(32'h8000_00b7, IMM_U, 32'h8000_0000, "U format 80000");
        check_immediate(32'hffff_f0b7, IMM_U, 32'hffff_f000, "U format fffff");
        check_immediate(32'hffff_ffff, IMM_RESERVED, 32'h0000_0000,
                        "reserved ImmSrcD");

        // Coloca ADD x3,x1,x2 no Decode e aplica um padrao nao nulo em cada
        // controle. A control_unit real so reconhece OP-IMM; este estimulo existe
        // apenas para provar que o registrador ID/EX transporta os fios.
        @(negedge clk);
        InstrF      = 32'h0020_81b3;
        ImmSrcD     = IMM_I;
        RegWriteD   = 1'b1;
        ResultSrcD  = 2'b10;
        MemWriteD   = 1'b1;
        StoreControlD = 3'b110;
        JumpD       = 1'b1;
        JalrD       = 1'b1;
        BranchD     = 1'b1;
        BranchControlD = 3'b111;
        ALUControlD = 4'b1101;
        ALUSrcD     = 1'b1;
        ALUASrcD    = 1'b1;
        @(posedge clk);
        #1;

        if ((OpD       !== 7'b0110011) || (Rs1D !== 5'd1) ||
            (Rs2D      !== 5'd2)       || (RdD  !== 5'd3) ||
            (Funct3D   !== 3'b000)     || (Funct7b5D !== 1'b0)) begin
            $fatal(1, "FAIL Decode: ADD fields were not extracted correctly");
        end
        if ((RD1D !== 32'h1111_1000) || (RD2D !== 32'h2222_2000)) begin
            $fatal(1, "FAIL Decode: Register File data did not reach RD1D/RD2D");
        end
        $display("PASS: Decode fields and Register File reads remain correct");

        // Congelar o IF/ID mantem os sinais D estaveis enquanto o ID/EX tira
        // sua fotografia no clock seguinte. Nao existe StallE no diagrama.
        @(negedge clk);
        StallD = 1'b1;
        @(posedge clk);
        check_id_ex_transfer();
        // Primeiro clock: o padrao conferido em E chega a M; W recebe o M anterior.
        check_late_pipeline_transfer();
        // Segundo clock: o mesmo padrao agora chega a W. A repeticao e intencional.
        check_late_pipeline_transfer();

        @(negedge clk);
        FlushE = 1'b1;
        @(posedge clk);
        check_id_ex_clear();

        // Prepara valores pequenos para deixar os calculos do Execute faceis
        // de acompanhar: x1=10 e x2=20.
        prepare_register(5'd1, 32'h00a0_0093, IMM_I, 4'b0000, 32'd10);
        prepare_register(5'd2, 32'h0140_0113, IMM_I, 4'b0000, 32'd20);

        // Reinicia apenas PC e registradores de pipeline. O Register File nao
        // possui reset e conserva os valores 10 e 20 escritos acima.
        @(negedge clk);
        reset       = 1'b1;
        FlushE      = 1'b0;
        StallD      = 1'b0;
        FlushD      = 1'b0;
        InstrF      = 32'b0;
        RegWriteD   = 1'b0;
        ResultSrcD  = 2'b00;
        MemWriteD   = 1'b0;
        StoreControlD = 3'b000;
        JumpD       = 1'b0;
        JalrD       = 1'b0;
        BranchD     = 1'b0;
        BranchControlD = 3'b000;
        ALUControlD = 4'b0000;
        ALUSrcD     = 1'b0;
        ALUASrcD    = 1'b0;
        ImmSrcD     = IMM_I;
        @(posedge clk);
        #1;
        check_late_pipeline_reset();

        // Caso registrador-registrador: ADD recebe x1=10 e x2=20.
        @(negedge clk);
        reset       = 1'b0;
        InstrF      = 32'h0020_81b3;
        ALUControlD = 4'b0000;
        ALUSrcD     = 1'b0;
        ImmSrcD     = IMM_I;
        @(posedge clk);
        @(negedge clk);
        StallD = 1'b1;
        @(posedge clk);
        check_execute(32'd10, 32'd20, 32'd20, 32'd30, 1'b0,
                      "Execute register-register ADD");

        // Caso imediato: x1=10 e imediato 5. Este teste estrutural aplica
        // ALUSrcD e ALUControlD diretamente, sem instanciar a control_unit.
        @(negedge clk);
        StallD      = 1'b0;
        InstrF      = 32'h0050_8093;
        ALUControlD = 4'b0000;
        ALUSrcD     = 1'b1;
        ImmSrcD     = IMM_I;
        @(posedge clk);
        @(negedge clk);
        StallD = 1'b1;
        @(posedge clk);
        #1;
        if ((SrcAE !== 32'd10) || (SrcBE !== 32'd5) ||
            (ALUResultE !== 32'd15)) begin
            $fatal(1, "FAIL Execute immediate: SrcAE=%h SrcBE=%h ALUResultE=%h",
                   SrcAE, SrcBE, ALUResultE);
        end
        $display("PASS: Execute immediate ADD");

        // SUB x1-x1 exercita ZeroE sem implementar comparacao de branch.
        @(negedge clk);
        StallD      = 1'b0;
        InstrF      = 32'h0010_8033;
        ALUControlD = 4'b0001;
        ALUSrcD     = 1'b0;
        @(posedge clk);
        @(negedge clk);
        StallD = 1'b1;
        @(posedge clk);
        #1;
        if ((ALUResultE !== 32'b0) || (ZeroE !== 1'b1)) begin
            $fatal(1, "FAIL Execute ZeroE: ALUResultE=%h ZeroE=%b",
                   ALUResultE, ZeroE);
        end
        $display("PASS: Execute ZeroE");

        // Reinicia o PC e avanca ate 100 para conferir o somador de alvo com
        // um imediato J de 16: PCTargetE deve ser 100 + 16 = 116.
        @(negedge clk);
        reset  = 1'b1;
        StallD = 1'b0;
        InstrF = 32'b0;
        @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        repeat (25) @(posedge clk);
        @(negedge clk);
        if (PCF !== 32'd100) begin
            $fatal(1, "FAIL PCTarget setup: PCF=%h expected=00000064", PCF);
        end
        InstrF      = 32'h0100_006f;
        ImmSrcD     = IMM_J;
        ALUControlD = 4'b0000;
        ALUSrcD     = 1'b1;
        @(posedge clk);
        @(negedge clk);
        StallD = 1'b1;
        @(posedge clk);
        #1;
        if ((PCE !== 32'd100) || (ImmExtE !== 32'd16) ||
            (PCTargetE !== 32'd116)) begin
            $fatal(1, "FAIL PCTargetE: PCE=%h ImmExtE=%h PCTargetE=%h",
                   PCE, ImmExtE, PCTargetE);
        end
        $display("PASS: PCTargetE = PCE + ImmExtE");

        // O IF/ID ainda guarda PCD=100 e imediato=16, logo PC+4=104.
        // As fontes de memoria e PC+4 sao testes de fios, nao de LOAD/JAL.
        check_wb_mux(2'b00, 32'd16);
        check_wb_mux(2'b01, 32'h1234_5678);
        check_wb_mux(2'b10, 32'd104);
        check_wb_mux(2'b11, 32'b0);

        @(negedge clk);
        reset = 1'b1;
        @(posedge clk);
        #1;
        check_late_pipeline_reset();

        $display("PASS: all Decode, Extend, pipeline and Execute tests completed");
        $finish;
    end

endmodule
