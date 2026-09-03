module datapath (
    input  logic clk,
    input  logic reset,
    input  logic test_i,
    output logic test_o
);

    // esse é apenas um sinal de teste
    assign test_o = ~test_i;

endmodule
