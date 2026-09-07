`timescale 1ns/1ps

module tb_hazard_unit;
    logic clk;
    logic reset;
    logic [4:0] Rs1D;
    logic [4:0] Rs2D;
    logic [4:0] Rs1E;
    logic [4:0] Rs2E;
    logic [4:0] RdE;
    logic [4:0] RdM;
    logic       RegWriteM;
    logic [4:0] RdW;
    logic       RegWriteW;
    logic       PCSrcE;
    logic [1:0] ResultSrcE;
    logic StallF;
    logic StallD;
    logic FlushD;
    logic FlushE;
    logic [1:0] ForwardAE;
    logic [1:0] ForwardBE;

    hazard_unit dut (
        .clk(clk), .reset(reset), .Rs1D(Rs1D), .Rs2D(Rs2D),
        .Rs1E(Rs1E), .Rs2E(Rs2E), .RdE(RdE),
        .RdM(RdM), .RegWriteM(RegWriteM), .RdW(RdW), .RegWriteW(RegWriteW),
        .PCSrcE(PCSrcE), .ResultSrcE(ResultSrcE),
        .StallF(StallF), .StallD(StallD), .FlushD(FlushD), .FlushE(FlushE),
        .ForwardAE(ForwardAE), .ForwardBE(ForwardBE)
    );

    task automatic check_forwarding (
        input logic [1:0] expected_a,
        input logic [1:0] expected_b,
        input string test_name
    );
        begin
            #1;
            if ((ForwardAE !== expected_a) || (ForwardBE !== expected_b))
                $fatal(1, "FAIL %s: ForwardAE=%b ForwardBE=%b",
                       test_name, ForwardAE, ForwardBE);
            if ({StallF, StallD, FlushD, FlushE} !== 4'b0000)
                $fatal(1, "FAIL %s: stall/flush must remain neutral", test_name);
            if ((ForwardAE === 2'b11) || (ForwardBE === 2'b11))
                $fatal(1, "FAIL %s: reserved forwarding code generated", test_name);
            $display("PASS: %s -> A=%b B=%b", test_name, ForwardAE, ForwardBE);
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        Rs1D = 5'd1;
        Rs2D = 5'd2;
        Rs1E = 5'd5;
        Rs2E = 5'd6;
        RdE = 5'd3;
        RdM = 5'd5;
        RegWriteM = 1'b1;
        RdW = 5'd6;
        RegWriteW = 1'b1;
        PCSrcE = 1'b1;
        ResultSrcE = 2'b00;

        check_forwarding(2'b00, 2'b00, "reset keeps forwarding safe");

        reset = 1'b0;
        PCSrcE = 1'b0;
        RdM = 5'd10;
        RdW = 5'd11;
        check_forwarding(2'b00, 2'b00, "no register match");

        RdM = 5'd5;
        RdW = 5'd11;
        check_forwarding(2'b10, 2'b00, "EX/MEM to operand A");

        RdM = 5'd6;
        check_forwarding(2'b00, 2'b10, "EX/MEM to operand B");

        RdM = 5'd10;
        RdW = 5'd5;
        check_forwarding(2'b01, 2'b00, "MEM/WB to operand A");

        RdW = 5'd6;
        check_forwarding(2'b00, 2'b01, "MEM/WB to operand B");

        RdM = 5'd6;
        RdW = 5'd5;
        check_forwarding(2'b01, 2'b10, "A from W and B from M");

        RdM = 5'd5;
        RdW = 5'd6;
        check_forwarding(2'b10, 2'b01, "A from M and B from W");

        // Se M e W oferecem o mesmo registrador, M deve vencer por ser mais novo.
        Rs1E = 5'd7;
        Rs2E = 5'd7;
        RdM = 5'd7;
        RdW = 5'd7;
        check_forwarding(2'b10, 2'b10, "EX/MEM priority over MEM/WB");

        Rs1E = 5'd0;
        Rs2E = 5'd0;
        RdM = 5'd0;
        RdW = 5'd0;
        check_forwarding(2'b00, 2'b00, "x0 never forwards");

        Rs1E = 5'd9;
        Rs2E = 5'd10;
        RdM = 5'd9;
        RdW = 5'd10;
        RegWriteM = 1'b0;
        RegWriteW = 1'b0;
        check_forwarding(2'b00, 2'b00, "RegWrite disabled blocks matches");

        // Um match desabilitado em M nao pode esconder um match valido em W.
        Rs1E = 5'd12;
        Rs2E = 5'd13;
        RdM = 5'd12;
        RdW = 5'd12;
        RegWriteM = 1'b0;
        RegWriteW = 1'b1;
        check_forwarding(2'b01, 2'b00, "disabled M falls back to valid W");

        // O redirect de JAL limpa IF/ID e ID/EX, sem ativar nenhum stall.
        Rs1E = 5'd1;
        Rs2E = 5'd2;
        RdM = 5'd10;
        RdW = 5'd11;
        RegWriteM = 1'b1;
        RegWriteW = 1'b1;
        PCSrcE = 1'b1;
        #1;
        if ((ForwardAE !== 2'b00) || (ForwardBE !== 2'b00) ||
            {StallF, StallD} !== 2'b00 || {FlushD, FlushE} !== 2'b11)
            $fatal(1, "FAIL: JAL control flush");
        $display("PASS: PCSrcE flushes Decode and Execute without stalls");

        PCSrcE = 1'b0;
        check_forwarding(2'b00, 2'b00, "flush returns to zero after redirect");

        $display("PASS: hazard_unit forwarding and JAL flush tests completed");
        $finish;
    end
endmodule
