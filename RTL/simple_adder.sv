module simple_adder #(
    parameter WIDTH = 8
) (
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    output logic [WIDTH:0]   sum
);

    always_comb begin
        sum = a + b;
    end

endmodule
