`timescale 1ns/1ps

module tb_fetch;

    logic        clk;
    logic        reset;
    logic        StallF;
    logic        StallD;
    logic        FlushD;
    logic        FlushE;
    logic [31:0] PCF;
    logic [31:0] PCPlus4F;
    logic [31:0] InstrF;
    logic [31:0] InstrD;
    logic [31:0] PCD;
    logic [31:0] PCPlus4D;

    // As demais portas do datapath continuam presentes, mas nao participam
    // deste teste focado exclusivamente nos estagios Fetch e Decode.
    logic [31:0] alu_result;
    logic        alu_zero;
    logic        alu_negative;
    logic        alu_carry;
    logic        alu_overflow;
    logic [6:0]  OpD;
    logic [4:0]  RdD;
    logic [2:0]  Funct3D;
    logic [4:0]  Rs1D;
    logic [4:0]  Rs2D;
    logic        Funct7b5D;
    logic [31:0] RD1D;
    logic [31:0] RD2D;

    instruction_memory #(
        .MEM_BYTES (2048),
        .INIT_FILE ("../mem/program.hex")
    ) u_instruction_memory (
        .clk   (clk),
        .en    (1'b1),
        .addr  (PCF),
        .rdata (InstrF)
    );

    datapath dut (
        .clk          (clk),
        .reset        (reset),
        .alu_a        (32'b0),
        .alu_b        (32'b0),
        .alu_op       (4'b1111),
        .alu_result   (alu_result),
        .alu_zero     (alu_zero),
        .alu_negative (alu_negative),
        .alu_carry    (alu_carry),
        .alu_overflow (alu_overflow),
        .rd_addr      (5'b0),
        .rd_data      (32'b0),
        .rd_we        (1'b0),
        .InstrF       (InstrF),
        .RegWriteD    (1'b0),
        .ResultSrcD   (2'b00),
        .MemWriteD    (1'b0),
        .JumpD        (1'b0),
        .BranchD      (1'b0),
        .ALUControlD  (3'b000),
        .ALUSrcD      (1'b0),
        .ImmSrcD      (2'b00),
        .StallF       (StallF),
        .StallD       (StallD),
        .FlushD       (FlushD),
        .FlushE       (FlushE),
        .ForwardAE    (2'b00),
        .ForwardBE    (2'b00),
        .PCSrcE       (),
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
        .ImmExtD      (),
        .RD1E         (),
        .RD2E         (),
        .PCE          (),
        .Rs1E         (),
        .Rs2E         (),
        .RdE          (),
        .ImmExtE      (),
        .PCPlus4E     (),
        .RegWriteE    (),
        .ResultSrcE   (),
        .MemWriteE    (),
        .JumpE        (),
        .BranchE      (),
        .ALUControlE  (),
        .ALUSrcE      ()
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check_fetch (
        input logic [31:0] expected_pcf,
        input logic [31:0] expected_instrf,
        input logic [31:0] expected_instrd,
        input logic [31:0] expected_pcd,
        input logic [31:0] expected_pcplus4d,
        input string       test_name
    );
        begin
            #1;
            if ((PCF      !== expected_pcf)      ||
                (PCPlus4F !== (expected_pcf + 32'd4)) ||
                (InstrF   !== expected_instrf)   ||
                (InstrD   !== expected_instrd)   ||
                (PCD      !== expected_pcd)      ||
                (PCPlus4D !== expected_pcplus4d)) begin
                $fatal(1,
                    "FAIL %s: PCF=%h InstrF=%h InstrD=%h PCD=%h PCPlus4D=%h",
                    test_name, PCF, InstrF, InstrD, PCD, PCPlus4D);
            end
            $display("PASS: %s", test_name);
        end
    endtask

    initial begin
        reset  = 1'b1;
        StallF = 1'b0;
        StallD = 1'b0;
        FlushD = 1'b0;
        FlushE = 1'b0;

        @(posedge clk);
        check_fetch(32'h0000_0000, 32'h0010_0093, 32'b0,
                    32'b0, 32'b0, "reset clears IF/ID");

        @(negedge clk);
        reset = 1'b0;

        // A cada clock, o PC avanca e o IF/ID guarda a instrucao anterior
        // junto dos enderecos que pertencem a ela.
        @(posedge clk);
        check_fetch(32'h0000_0004, 32'h0020_0113, 32'h0010_0093,
                    32'h0000_0000, 32'h0000_0004, "fetch address 0");
        @(posedge clk);
        check_fetch(32'h0000_0008, 32'h0020_81b3, 32'h0020_0113,
                    32'h0000_0004, 32'h0000_0008, "fetch address 4");
        @(posedge clk);
        check_fetch(32'h0000_000c, 32'h0000_0013, 32'h0020_81b3,
                    32'h0000_0008, 32'h0000_000c, "fetch address 8");

        // StallD congela somente o IF/ID. O PC continua avancando porque
        // StallF permanece inativo neste teste.
        @(negedge clk);
        StallD = 1'b1;
        @(posedge clk);
        #1;
        if ((PCF !== 32'h0000_0010) ||
            (InstrD !== 32'h0020_81b3) ||
            (PCD !== 32'h0000_0008) ||
            (PCPlus4D !== 32'h0000_000c)) begin
            $fatal(1, "FAIL StallD: IF/ID changed while stalled");
        end
        $display("PASS: StallD freezes IF/ID");

        // FlushD tem prioridade sobre StallD e insere uma bolha no Decode.
        @(negedge clk);
        FlushD = 1'b1;
        @(posedge clk);
        #1;
        if ((InstrD !== 32'b0) || (PCD !== 32'b0) || (PCPlus4D !== 32'b0)) begin
            $fatal(1, "FAIL FlushD: IF/ID was not cleared");
        end
        $display("PASS: FlushD clears IF/ID");

        $display("PASS: all Fetch and IF/ID tests completed");
        $finish;
    end

endmodule
