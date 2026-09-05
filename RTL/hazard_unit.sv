module hazard_unit (
    input  logic clk,
    input  logic reset,
    output logic StallD,
    output logic FlushD
);

    // A unidade ainda e apenas um esqueleto. Estes sinais ja seguem os nomes
    // do diagrama e serao controlados pela deteccao real de hazards no futuro.
    assign StallD = 1'b0;
    assign FlushD = 1'b0;

endmodule
