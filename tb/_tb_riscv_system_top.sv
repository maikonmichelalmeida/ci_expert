module tb_riscv_system_top;

    logic clk;
    logic reset;
    logic test;
    logic test_return;

    riscv_system_top dut (
        .clk    (clk),
        .reset  (reset),
        .test_i (test),
        .test_o (test_return)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $fsdbDumpfile("test.fsdb");
        $fsdbDumpvars(0, tb_riscv_system_top);
        $fsdbDumpMDA(0, tb_riscv_system_top);
    end

    initial begin
        $display("=== RV32I SKELETON CONNECTIVITY TEST ===");

        reset = 1'b1;
        test  = 1'b0;
        #10;
        reset = 1'b0;
        #1;

        if (test_return !== 1'b1)
            $fatal(1, "FAIL: test=0, expected test_return=1");

        test = 1'b1;
        #1;

        if (test_return !== 1'b0)
            $fatal(1, "FAIL: test=1, expected test_return=0");

        $display("PASS: clock and reset reached the module hierarchy");
        $display("PASS: test passed through the datapath and returned inverted");
        $display("=== TEST FINISHED ===");
        $finish;
    end

endmodule
