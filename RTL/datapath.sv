// Caminho de dados do core. Neste ponto do projeto ele reune PC, IF/ID, ALU
// e banco de registradores, preservando os nomes usados no diagrama do pipeline.
module datapath (
    input  logic clk,
    input  logic reset,
    input  logic [31:0] alu_a,
    input  logic [31:0] alu_b,
    input  logic [3:0]  alu_op,
    output logic [31:0] alu_result,
    output logic        alu_zero,
    output logic        alu_negative,
    output logic        alu_carry,
    output logic        alu_overflow,
    input  logic [4:0]  rs1_addr,
    input  logic [4:0]  rs2_addr,
    input  logic [4:0]  rd_addr,
    input  logic [31:0] rd_data,
    input  logic        rd_we,
    output logic [31:0] rs1_data,
    output logic [31:0] rs2_data,
    input  logic [31:0] InstrF,
    input  logic        StallD,
    input  logic        FlushD,
    output logic [31:0] PCF,
    output logic [31:0] PCPlus4F,
    output logic [31:0] InstrD,
    output logic [31:0] PCD,
    output logic [31:0] PCPlus4D
);

    // Sinais ao redor do PC no diagrama: PCSrcE controla o mux, PCTargetE sera
    // o endereco alternativo e StallF sera o enable invertido do registrador PC.
    logic        PCSrcE;
    logic [31:0] PCTargetE;
    logic        StallF;
    logic [31:0] PCNextF;

    // Estes sinais serao ligados ao controle de branch e hazards em etapas futuras.
    // Por enquanto, zeros significam sempre escolher PCPlus4F e nunca travar PCF.
    assign PCSrcE    = 1'b0;
    assign PCTargetE = 32'b0;
    assign StallF    = 1'b0;

    // O submodulo pc implementa o registrador PCF, o somador PC+4 e o mux
    // PCNextF. O datapath apenas transporta esses sinais entre os estagios.
    pc u_pc (
        .clk       (clk),
        .reset     (reset),
        .PCSrcE    (PCSrcE),
        .PCTargetE (PCTargetE),
        .StallF    (StallF),
        .PCF       (PCF),
        .PCPlus4F  (PCPlus4F),
        .PCNextF   (PCNextF)
    );

    // Registrador de pipeline IF/ID.
    // InstrD guarda a instrucao buscada, enquanto PCD e PCPlus4D guardam os
    // enderecos que pertencem a essa mesma instrucao no estagio Decode.
    // Exemplo: se InstrF esta em PCF=8, no clock sao guardados PCD=8 e
    // PCPlus4D=12 junto com essa instrucao, mesmo que PCF avance para 12.
    always_ff @(posedge clk) begin
        // Flush possui prioridade sobre Stall para remover uma instrucao invalida.
        // Zerar os tres campos equivale a inserir uma bolha no estagio Decode.
        if (reset || FlushD) begin
            InstrD   <= 32'b0;
            PCD      <= 32'b0;
            PCPlus4D <= 32'b0;
        end else if (!StallD) begin
            // No fluxo normal, os sinais com sufixo F atravessam a fronteira
            // de pipeline e passam a ter o sufixo D depois deste flanco.
            InstrD   <= InstrF;
            PCD      <= PCF;
            PCPlus4D <= PCPlus4F;
        end
        // Com StallD ativo nao ha atribuicao: o IF/ID conserva seus valores.
    end

    // Nesta etapa, os operandos e o controle da ULA ainda sao portas de teste.
    // A instancia preserva o local definitivo da ALU dentro do datapath.
    alu u_alu (
        .a        (alu_a),
        .b        (alu_b),
        .alu_op   (alu_op),
        .result   (alu_result),
        .zero     (alu_zero),
        .negative (alu_negative),
        .carry    (alu_carry),
        .overflow (alu_overflow)
    );

    // Nesta etapa, as portas do banco de registradores tambem sao de teste.
    // Futuramente rs1/rs2 virao dos campos de InstrD e rd sera o destino do WB.
    register_file u_register_file (
        .clk      (clk),
        .rs1_addr (rs1_addr),
        .rs2_addr (rs2_addr),
        .rd_addr  (rd_addr),
        .rd_data  (rd_data),
        .rd_we    (rd_we),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data)
    );

endmodule
