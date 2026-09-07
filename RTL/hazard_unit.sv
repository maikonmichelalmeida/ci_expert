// Detector de dependencias do pipeline.
// Forwarding e flush de JAL/JALR sao funcionais; os stalls continuam inativos.
module hazard_unit (
    input  logic clk,
    input  logic reset,
    input  logic [4:0] Rs1D,
    input  logic [4:0] Rs2D,
    input  logic [4:0] Rs1E,
    input  logic [4:0] Rs2E,
    input  logic [4:0] RdE,
    input  logic [4:0] RdM,
    input  logic       RegWriteM,
    input  logic [4:0] RdW,
    input  logic       RegWriteW,
    input  logic       PCSrcE,
    input  logic [1:0] ResultSrcE,
    output logic StallF,
    output logic StallD,
    output logic FlushD,
    output logic FlushE,
    output logic [1:0] ForwardAE,
    output logic [1:0] ForwardBE
);

    always_comb begin
        // 00 escolhe os valores originais do ID/EX. Os stalls continuam
        // neutros porque load-use ainda nao pertence a esta etapa.
        StallF    = 1'b0;
        StallD    = 1'b0;
        FlushD    = 1'b0;
        FlushE    = 1'b0;
        ForwardAE = 2'b00;
        ForwardBE = 2'b00;

        if (!reset) begin
            // Quando um jump chega a EX, descarta as duas instrucoes mais jovens:
            // uma esta em Decode e a outra acaba de ser buscada pelo Fetch.
            FlushD = PCSrcE;
            FlushE = PCSrcE;

            // EX/MEM tem prioridade porque guarda o resultado mais recente.
            // Rd=0 nunca encaminha: x0 deve continuar valendo zero.
            if (RegWriteM && (RdM != 5'b00000) && (RdM == Rs1E))
                ForwardAE = 2'b10;
            else if (RegWriteW && (RdW != 5'b00000) && (RdW == Rs1E))
                ForwardAE = 2'b01;

            if (RegWriteM && (RdM != 5'b00000) && (RdM == Rs2E))
                ForwardBE = 2'b10;
            else if (RegWriteW && (RdW != 5'b00000) && (RdW == Rs2E))
                ForwardBE = 2'b01;
        end
    end

    // Rs1D, Rs2D, RdE e ResultSrcE permanecem na interface para as futuras
    // regras de load-use. PCSrcE ja produz o flush do primeiro hazard de controle.

endmodule
