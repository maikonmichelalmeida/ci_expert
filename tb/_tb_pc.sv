`timescale 1ns/1ps

module tb_pc;

    logic        clk;
    logic        reset;
    logic        PCSrcE;
    logic [31:0] PCTargetE;
    logic        StallF;
    logic [31:0] PCF;
    logic [31:0] PCPlus4F;
    logic [31:0] PCNextF;

    pc dut (
        .clk       (clk),
        .reset     (reset),
        .PCSrcE    (PCSrcE),
        .PCTargetE (PCTargetE),
        .StallF    (StallF),
        .PCF       (PCF),
        .PCPlus4F  (PCPlus4F),
        .PCNextF   (PCNextF)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check_pc (
        input logic [31:0] expected,
        input string       test_name
    );
        begin
            #1;
            if (PCF !== expected) begin
                $fatal(1, "FAIL %s: PCF=%h expected=%h", test_name, PCF, expected);
            end
            $display("PASS: %s PCF=%h", test_name, PCF);
        end
    endtask

    initial begin
        reset     = 1'b1;
        PCSrcE    = 1'b0;
        PCTargetE = 32'b0;
        StallF    = 1'b0;

        @(posedge clk);
        check_pc(32'h0000_0000, "reset");

        @(negedge clk);
        reset = 1'b0;
        check_pc(32'h0000_0000, "first fetch address");

        @(posedge clk);
        check_pc(32'h0000_0004, "sequential step 1");
        @(posedge clk);
        check_pc(32'h0000_0008, "sequential step 2");
        @(posedge clk);
        check_pc(32'h0000_000c, "sequential step 3");

        // A trava segura PCF mesmo que PCNextF ja aponte para a proxima palavra.
        @(negedge clk);
        StallF = 1'b1;
        #1;
        if ((PCPlus4F !== 32'h0000_0010) || (PCNextF !== 32'h0000_0010)) begin
            $fatal(1, "FAIL next PC logic while stalled");
        end
        @(posedge clk);
        check_pc(32'h0000_000c, "StallF freezes PCF");

        @(negedge clk);
        StallF = 1'b0;
        @(posedge clk);
        check_pc(32'h0000_0010, "resume after StallF");

        // Exercita somente o mux previsto para o futuro branch/jump.
        @(negedge clk);
        PCSrcE    = 1'b1;
        PCTargetE = 32'h0000_0040;
        #1;
        if (PCNextF !== 32'h0000_0040) begin
            $fatal(1, "FAIL PCSrcE mux: PCNextF=%h", PCNextF);
        end
        @(posedge clk);
        check_pc(32'h0000_0040, "PCSrcE selects PCTargetE");

        $display("PASS: all PC tests completed");
        $finish;
    end

endmodule
