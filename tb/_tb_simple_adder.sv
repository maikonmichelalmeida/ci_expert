module tb_simple_adder;

    logic [7:0] a;
    logic [7:0] b;
    logic [8:0] sum;

    simple_adder dut (
        .a   (a),
        .b   (b),
        .sum (sum)
    );

    initial begin
        $fsdbDumpfile("test.fsdb");
        $fsdbDumpvars(0, tb_simple_adder);
        $fsdbDumpMDA(0, tb_simple_adder);
    end

    initial begin
        $display("=== SIMPLE ADDER SMOKE TEST ===");

        a = 8'd10;
        b = 8'd5;
        #1;

        if (sum !== 9'd15)
            $error("FAIL: 10 + 5 = %0d (expected 15)", sum);
        else
            $display("PASS: 10 + 5 = %0d", sum);

        a = 8'd200;
        b = 8'd100;
        #1;

        if (sum !== 9'd300)
            $error("FAIL: 200 + 100 = %0d (expected 300)", sum);
        else
            $display("PASS: 200 + 100 = %0d", sum);

        #20;
        $display("=== TEST FINISHED ===");
        $finish;
    end

endmodule
