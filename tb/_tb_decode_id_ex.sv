`timescale 1ns/1ps

// Teste estrutural do Decode e do registrador ID/EX.
// Ele instancia o datapath diretamente para poder aplicar controles D nao
// nulos sem transformar a control_unit em um decoder funcional antes da hora.
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
    logic       JumpD;
    logic       BranchD;
    logic [3:0] ALUControlD;
    logic       ALUSrcD;
    logic [2:0] ImmSrcD;

    logic       StallF;
    logic       StallD;
    logic       FlushD;
    logic       FlushE;
    logic [1:0] ForwardAE;
    logic [1:0] ForwardBE;

    logic [4:0]  rd_addr;
    logic [31:0] rd_data;
    logic        rd_we;

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
    logic        JumpE;
    logic        BranchE;
    logic [3:0]  ALUControlE;
    logic        ALUSrcE;
    logic [31:0] SrcAE;
    logic [31:0] WriteDataE;
    logic [31:0] SrcBE;
    logic [31:0] ALUResultE;
    logic        ZeroE;
    logic [31:0] PCTargetE;

    datapath dut (
        .clk          (clk),
        .reset        (reset),
        .rd_addr      (rd_addr),
        .rd_data      (rd_data),
        .rd_we        (rd_we),
        .InstrF       (InstrF),
        .RegWriteD    (RegWriteD),
        .ResultSrcD   (ResultSrcD),
        .MemWriteD    (MemWriteD),
        .JumpD        (JumpD),
        .BranchD      (BranchD),
        .ALUControlD  (ALUControlD),
        .ALUSrcD      (ALUSrcD),
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
        .JumpE        (JumpE),
        .BranchE      (BranchE),
        .ALUControlE  (ALUControlE),
        .ALUSrcE      (ALUSrcE),
        .SrcAE        (SrcAE),
        .WriteDataE   (WriteDataE),
        .SrcBE        (SrcBE),
        .ALUResultE   (ALUResultE),
        .ZeroE        (ZeroE)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

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
                (JumpE       !== JumpD)      ||
                (BranchE     !== BranchD)    ||
                (ALUControlE !== ALUControlD)||
                (ALUSrcE     !== ALUSrcD)) begin
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
                (BranchE     !== 1'b0)  || (ALUControlE!== 4'b0000)||
                (ALUSrcE     !== 1'b0)) begin
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
        JumpD       = 1'b0;
        BranchD     = 1'b0;
        ALUControlD = 4'b0000;
        ALUSrcD     = 1'b0;
        ImmSrcD     = IMM_I;
        StallF      = 1'b0;
        StallD      = 1'b0;
        FlushD      = 1'b0;
        FlushE      = 1'b0;
        ForwardAE   = 2'b00;
        ForwardBE   = 2'b00;
        rd_addr     = 5'b0;
        rd_data     = 32'b0;
        rd_we       = 1'b0;

        // Prepara dois valores conhecidos no caminho temporario de escrita.
        write_register(5'd1, 32'h1111_1111);
        write_register(5'd2, 32'h2222_2222);

        @(negedge clk);
        reset = 1'b0;

        // Cada instrucao abaixo exercita uma montagem diferente do Extend.
        check_immediate(32'hfff0_0093, IMM_I, 32'hffff_ffff, "I format -1");
        check_immediate(32'hfe20_ae23, IMM_S, 32'hffff_fffc, "S format -4");
        check_immediate(32'h0000_0463, IMM_B, 32'h0000_0008, "B format +8");
        check_immediate(32'h0100_006f, IMM_J, 32'h0000_0010, "J format +16");
        check_immediate(32'h1234_50b7, IMM_U, 32'h1234_5000, "U format");
        check_immediate(32'hffff_ffff, IMM_RESERVED, 32'h0000_0000,
                        "reserved ImmSrcD");

        // Coloca ADD x3,x1,x2 no Decode e aplica um padrao nao nulo em cada
        // controle. A control_unit real continua neutra; este estimulo existe
        // apenas para provar que o registrador ID/EX transporta os fios.
        @(negedge clk);
        InstrF      = 32'h0020_81b3;
        ImmSrcD     = IMM_I;
        RegWriteD   = 1'b1;
        ResultSrcD  = 2'b10;
        MemWriteD   = 1'b1;
        JumpD       = 1'b1;
        BranchD     = 1'b1;
        ALUControlD = 4'b1101;
        ALUSrcD     = 1'b1;
        @(posedge clk);
        #1;

        if ((OpD       !== 7'b0110011) || (Rs1D !== 5'd1) ||
            (Rs2D      !== 5'd2)       || (RdD  !== 5'd3) ||
            (Funct3D   !== 3'b000)     || (Funct7b5D !== 1'b0)) begin
            $fatal(1, "FAIL Decode: ADD fields were not extracted correctly");
        end
        if ((RD1D !== 32'h1111_1111) || (RD2D !== 32'h2222_2222)) begin
            $fatal(1, "FAIL Decode: Register File data did not reach RD1D/RD2D");
        end
        $display("PASS: Decode fields and Register File reads remain correct");

        // Congelar o IF/ID mantem os sinais D estaveis enquanto o ID/EX tira
        // sua fotografia no clock seguinte. Nao existe StallE no diagrama.
        @(negedge clk);
        StallD = 1'b1;
        @(posedge clk);
        check_id_ex_transfer();

        @(negedge clk);
        FlushE = 1'b1;
        @(posedge clk);
        check_id_ex_clear();

        // Prepara valores pequenos para deixar os calculos do Execute faceis
        // de acompanhar: x1=10 e x2=20.
        write_register(5'd1, 32'd10);
        write_register(5'd2, 32'd20);

        // Reinicia apenas PC e registradores de pipeline. O Register File nao
        // possui reset e conserva os valores 10 e 20 escritos acima.
        @(negedge clk);
        reset       = 1'b1;
        FlushE      = 1'b0;
        StallD      = 1'b0;
        FlushD      = 1'b0;
        InstrF      = 32'b0;
        ALUControlD = 4'b0000;
        ALUSrcD     = 1'b0;
        ImmSrcD     = IMM_I;
        @(posedge clk);
        #1;

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

        // Caso imediato: ADDI fornece x1=10 e imediato 5. A control_unit nao
        // decodifica ADDI; o testbench aplica ALUSrcD e ALUControlD diretamente.
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

        $display("PASS: all Decode, Extend, ID/EX and Execute tests completed");
        $finish;
    end

endmodule
