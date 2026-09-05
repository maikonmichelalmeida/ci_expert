// Topo do sistema: conecta o core as memorias de instrucao e dados.
// As portas de ALU e register file ainda sao acessos de teste desta fase.
module riscv_system_top #(
    parameter IMEM_INIT_FILE = ""
)(
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
    output logic [31:0] rs2_data
);

    // data_rdata sera consumido pela futura LSU. Hoje a DMEM permanece isolada.
    logic [31:0] data_rdata;

    // Estes nomes reproduzem o caminho do diagrama. O sufixo F identifica
    // sinais do estagio Fetch; o sufixo D identifica a saida do IF/ID.
    logic [31:0] PCF;
    logic [31:0] PCPlus4F;
    logic [31:0] InstrF;
    logic [31:0] PCD;
    logic [31:0] PCPlus4D;
    logic [31:0] InstrD;

    // A IMEM permanece fora do core. Sua saida combinacional forma InstrF,
    // que entra no datapath e sera registrada no IF/ID no proximo clock.
    // IMEM_INIT_FILE e repassado sem alterar o conteudo: no testbench, por
    // exemplo, ele aponta para mem/program.hex.
    instruction_memory #(
        .INIT_FILE (IMEM_INIT_FILE)
    ) u_instruction_memory (
        .clk   (clk),
        .en    (1'b1),
        .addr  (PCF),
        .rdata (InstrF)
    );

    // O core recebe InstrF da memoria e devolve PCF como endereco da busca.
    // PCD, PCPlus4D e InstrD ficam prontos para o decoder que sera criado depois.
    riscv_core u_riscv_core (
        .clk          (clk),
        .reset        (reset),
        .alu_a        (alu_a),
        .alu_b        (alu_b),
        .alu_op       (alu_op),
        .alu_result   (alu_result),
        .alu_zero     (alu_zero),
        .alu_negative (alu_negative),
        .alu_carry    (alu_carry),
        .alu_overflow (alu_overflow),
        .rs1_addr     (rs1_addr),
        .rs2_addr     (rs2_addr),
        .rd_addr      (rd_addr),
        .rd_data      (rd_data),
        .rd_we        (rd_we),
        .rs1_data     (rs1_data),
        .rs2_data     (rs2_data),
        .InstrF       (InstrF),
        .PCF          (PCF),
        .PCPlus4F     (PCPlus4F),
        .InstrD       (InstrD),
        .PCD          (PCD),
        .PCPlus4D     (PCPlus4D)
    );

    // A DMEM ja ocupa seu lugar no sistema, mas fica desabilitada ate a LSU
    // fornecer endereco, dado de escrita e strobes validos.
    data_memory u_data_memory (
        .clk   (clk),
        .en    (1'b0),
        .addr  (32'b0),
        .wdata (32'b0),
        .wstrb (4'b0),
        .rdata (data_rdata)
    );

endmodule
