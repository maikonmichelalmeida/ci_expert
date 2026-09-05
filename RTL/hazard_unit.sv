// Futuro detector de dependencias e riscos do pipeline.
// Seus sinais de saida controlam quando o IF/ID deve parar ou ser limpo.
module hazard_unit (
    input  logic clk,
    input  logic reset,
    output logic StallD,
    output logic FlushD
);

    // A unidade ainda e apenas um esqueleto. Estes sinais ja seguem os nomes
    // do diagrama e serao controlados pela deteccao real de hazards no futuro.
    // StallD=0 permite que o IF/ID capture novos valores a cada clock.
    // FlushD=0 evita inserir bolhas enquanto branches ainda nao foram ligados.
    assign StallD = 1'b0;
    assign FlushD = 1'b0;

endmodule
