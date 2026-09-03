module riscv_core (
    input  logic clk,
    input  logic reset,
    input  logic test_i,
    output logic test_o
);

    datapath u_datapath (
        .clk    (clk),
        .reset  (reset),
        .test_i (test_i),
        .test_o (test_o)
    );

    control_unit u_control_unit (
        .clk   (clk),
        .reset (reset)
    );

    hazard_unit u_hazard_unit (
        .clk   (clk),
        .reset (reset)
    );

endmodule
