// Nucleo do processador: agrupa datapath, control_unit e hazard_unit.
// As memorias ficam fora deste modulo, conforme a hierarquia do diagrama.
module riscv_core (
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
    input  logic [4:0]  rd_addr,
    input  logic [31:0] rd_data,
    input  logic        rd_we,
    input  logic [31:0] InstrF,
    output logic [31:0] PCF,
    output logic [31:0] PCPlus4F,
    output logic [31:0] InstrD,
    output logic [31:0] PCD,
    output logic [31:0] PCPlus4D,
    output logic [6:0]  OpD,
    output logic [4:0]  RdD,
    output logic [2:0]  Funct3D,
    output logic [4:0]  Rs1D,
    output logic [4:0]  Rs2D,
    output logic        Funct7b5D,
    output logic [31:0] RD1D,
    output logic [31:0] RD2D
);

    // Estes fios levam as decisoes da hazard_unit ao registrador IF/ID.
    // Hoje ambos ficam em zero; os nomes ja reservam a conexao definitiva.
    logic StallD;
    logic FlushD;

    // A instrucao vem da IMEM externa ao core. Os sinais da hazard unit entram
    // no datapath para controlar diretamente o registrador de pipeline IF/ID.
    // Os sinais terminados em F pertencem ao Fetch; os terminados em D saem
    // registrados para o futuro estagio Decode.
    datapath u_datapath (
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
        .rd_addr      (rd_addr),
        .rd_data      (rd_data),
        .rd_we        (rd_we),
        .InstrF       (InstrF),
        .StallD       (StallD),
        .FlushD       (FlushD),
        .PCF          (PCF),
        .PCPlus4F     (PCPlus4F),
        .InstrD       (InstrD),
        .PCD          (PCD),
        .PCPlus4D     (PCPlus4D),
        .OpD          (OpD),
        .RdD          (RdD),
        .Funct3D      (Funct3D),
        .Rs1D         (Rs1D),
        .Rs2D         (Rs2D),
        .Funct7b5D    (Funct7b5D),
        .RD1D         (RD1D),
        .RD2D         (RD2D)
    );

    // A control_unit permanece posicionada na hierarquia, embora o decoder
    // ainda seja um esqueleto nesta etapa incremental.
    control_unit u_control_unit (
        .clk   (clk),
        .reset (reset)
    );

    // A hazard_unit sera a origem real dos stalls e flushes do pipeline.
    hazard_unit u_hazard_unit (
        .clk    (clk),
        .reset  (reset),
        .StallD (StallD),
        .FlushD (FlushD)
    );

endmodule
