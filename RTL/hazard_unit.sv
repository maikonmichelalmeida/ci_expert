// Detector de dependencias do pipeline.
// Forwarding e flush de redirects sao funcionais; os stalls continuam inativos.
module hazard_unit (
    input  logic clk,
    input  logic reset,
    input  logic [4:0] Rs1D,
    input  logic [4:0] Rs2D,
    input  logic       UsesRs1D,
    input  logic       UsesRs2D,
    input  logic       MemWriteD,
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

    logic LoadE;
    logic Rs1Hazard;
    logic Rs2Hazard;
    logic LoadUseHazard;

    always_comb begin
        // 00 escolhe os valores originais do ID/EX. Todos os controles recebem
        // defaults seguros antes das comparacoes de dependencia e redirect.
        StallF    = 1'b0;
        StallD    = 1'b0;
        FlushD    = 1'b0;
        FlushE    = 1'b0;
        ForwardAE = 2'b00;
        ForwardBE = 2'b00;
        LoadE         = 1'b0;
        Rs1Hazard     = 1'b0;
        Rs2Hazard     = 1'b0;
        LoadUseHazard = 1'b0;

        if (!reset) begin
            // ResultSrcE=01 identifica o LOAD que ainda espera a leitura em MEM.
            // STORE.rs2 fica fora do stall porque seu dado so e exigido em MEM
            // e recebe o bypass tardio ResultW -> StoreWriteDataM.
            LoadE         = (ResultSrcE == 2'b01);
            Rs1Hazard     = UsesRs1D && (RdE != 5'b00000) && (RdE == Rs1D);
            Rs2Hazard     = UsesRs2D && !MemWriteD &&
                            (RdE != 5'b00000) && (RdE == Rs2D);
            LoadUseHazard = LoadE && (Rs1Hazard || Rs2Hazard);

            // Quando um jump ou branch tomado chega a EX, descarta as duas
            // instrucoes mais jovens:
            // uma esta em Decode e a outra acaba de ser buscada pelo Fetch.
            // O redirect vence um load-use: nao faz sentido manter uma
            // instrucao que acabou de se tornar parte do caminho errado.
            StallF = LoadUseHazard && !PCSrcE;
            StallD = LoadUseHazard && !PCSrcE;
            FlushD = PCSrcE;
            FlushE = PCSrcE | LoadUseHazard;

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

    // Um load-use segura PC/IF-ID por um ciclo e limpa o ID/EX. O LOAD continua
    // para M/W; depois da bolha, o forwarding 01 entrega ResultW ao consumidor.

endmodule
