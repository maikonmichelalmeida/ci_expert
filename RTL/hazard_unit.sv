// Detector de dependencias do pipeline.
// Neste checkpoint somente o forwarding e funcional; stalls e flushes ficam zero.
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
        // 00 escolhe os valores originais do ID/EX. Stall e flush continuam
        // neutros porque load-use e riscos de controle ainda nao pertencem a etapa.
        StallF    = 1'b0;
        StallD    = 1'b0;
        FlushD    = 1'b0;
        FlushE    = 1'b0;
        ForwardAE = 2'b00;
        ForwardBE = 2'b00;

        if (!reset) begin
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

    // Rs1D, Rs2D, RdE, PCSrcE e ResultSrcE permanecem na interface para as
    // futuras regras de load-use e controle. Eles ainda nao geram stall/flush.

endmodule
