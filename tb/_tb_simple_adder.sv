module tb_simple_adder;

    logic [7:0] a;
    logic [7:0] b;
    logic [8:0] sum;

    simple_adder dut (
        .a(a),
        .b(b),
        .sum(sum)
    );

    initial begin
        a = 8'd10;
        b = 8'd5;
        #1;

        if (sum !== 9'd15)
            $error("ERRO: 10 + 5 = %0d", sum);
        else
            $display("PASS: 10 + 5 = %0d", sum);

        a = 8'd200;
        b = 8'd100;
        #1;

        if (sum !== 9'd300)
            $error("ERRO: 200 + 100 = %0d", sum);
        else
            $display("PASS: 200 + 100 = %0d", sum);

        $finish;
    end

endmodule
