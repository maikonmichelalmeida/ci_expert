module riscv_system_top (
    input  logic clk,
    input  logic reset,
    input  logic test_i,
    output logic test_o
);

    instruction_memory u_instruction_memory (
        .clk   (clk),
        .reset (reset)
    );

    riscv_core u_riscv_core (
        .clk    (clk),
        .reset  (reset),
        .test_i (test_i),
        .test_o (test_o)
    );

    data_memory u_data_memory (
        .clk   (clk),
        .reset (reset)
    );

endmodule
