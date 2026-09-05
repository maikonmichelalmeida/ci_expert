// Futuro detector de dependencias e riscos do pipeline.
// Sua interface ja possui stalls, flushes e selecoes de forwarding do diagrama.
module hazard_unit (
    input  logic clk,
    input  logic reset,
    input  logic [4:0] Rs1D,
    input  logic [4:0] Rs2D,
    input  logic [4:0] Rs1E,
    input  logic [4:0] Rs2E,
    input  logic [4:0] RdE,
    input  logic       PCSrcE,
    input  logic [1:0] ResultSrcE,
    output logic StallF,
    output logic StallD,
    output logic FlushD,
    output logic FlushE,
    output logic [1:0] ForwardAE,
    output logic [1:0] ForwardBE
);

    // A unidade continua sem inteligencia. Zeros sao os valores neutros:
    // os estagios avancam, nenhuma bolha e inserida e os futuros muxes de
    // forwarding escolherao sua entrada 00.
    assign StallF   = 1'b0;
    assign StallD   = 1'b0;
    assign FlushD   = 1'b0;
    assign FlushE   = 1'b0;
    assign ForwardAE = 2'b00;
    assign ForwardBE = 2'b00;

    // Os enderecos de registradores D/E, PCSrcE e ResultSrcE tambem ja chegam
    // ao bloco porque existem nesta fronteira do pipeline. Eles serao usados
    // futuramente; sinais dos estagios M/W so serao adicionados quando esses
    // estagios realmente existirem.

endmodule
