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

    logic        PCSrcE;
    logic [31:0] PCTargetE;
    logic        StallF;
    logic [31:0] PCNextF;

    // Estes sinais serao ligados ao controle de branch e hazards em etapas futuras.
    assign PCSrcE    = 1'b0;
    assign PCTargetE = 32'b0;
    assign StallF    = 1'b0;

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
    always_ff @(posedge clk) begin
        // Flush possui prioridade sobre Stall para remover uma instrucao invalida.
        if (reset || FlushD) begin
            InstrD   <= 32'b0;
            PCD      <= 32'b0;
            PCPlus4D <= 32'b0;
        end else if (!StallD) begin
            InstrD   <= InstrF;
            PCD      <= PCF;
            PCPlus4D <= PCPlus4F;
        end
        // Com StallD ativo nao ha atribuicao: o IF/ID conserva seus valores.
    end

    // Nesta etapa, os sinais da ULA apenas atravessam o datapath.
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
