// Topo do sistema: conecta o core as memorias de instrucao e dados.
// As portas da ALU e a escrita do register file ainda sao acessos de teste.
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
    input  logic [4:0]  rd_addr,
    input  logic [31:0] rd_data,
    input  logic        rd_we
);

    // data_rdata sera consumido pela futura LSU. Hoje a DMEM permanece isolada.
    logic [31:0] data_rdata;

    // Estes nomes reproduzem o caminho do diagrama. O sufixo F identifica
    // sinais do estagio Fetch; o sufixo D identifica o estagio Decode.
    logic [31:0] PCF;
    logic [31:0] PCPlus4F;
    logic [31:0] InstrF;
    logic [31:0] PCD;
    logic [31:0] PCPlus4D;
    logic [31:0] InstrD;

    // Campos fixos extraidos de InstrD e dados lidos no Register File.
    // Eles permanecem visiveis no topo para acompanhar o diagrama e os testes.
    logic [6:0]  OpD;
    logic [4:0]  RdD;
    logic [2:0]  Funct3D;
    logic [4:0]  Rs1D;
    logic [4:0]  Rs2D;
    logic        Funct7b5D;
    logic [31:0] RD1D;
    logic [31:0] RD2D;
    logic [31:0] ImmExtD;

    // Saidas do novo registrador ID/EX. Elas ainda nao alimentam a ALU real;
    // ficam nomeadas e posicionadas para a proxima etapa do pipeline.
    logic [31:0] RD1E;
    logic [31:0] RD2E;
    logic [31:0] PCE;
    logic [4:0]  Rs1E;
    logic [4:0]  Rs2E;
    logic [4:0]  RdE;
    logic [31:0] ImmExtE;
    logic [31:0] PCPlus4E;
    logic        RegWriteE;
    logic [1:0]  ResultSrcE;
    logic        MemWriteE;
    logic        JumpE;
    logic        BranchE;
    logic [3:0]  ALUControlE;
    logic        ALUSrcE;

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
    // Agora tambem entrega os dados e controles registrados na fronteira ID/EX.
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
        .rd_addr      (rd_addr),
        .rd_data      (rd_data),
        .rd_we        (rd_we),
        .InstrF       (InstrF),
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
        .RD2D         (RD2D),
        .ImmExtD      (ImmExtD),
        .RD1E         (RD1E),
        .RD2E         (RD2E),
        .PCE          (PCE),
        .Rs1E         (Rs1E),
        .Rs2E         (Rs2E),
        .RdE          (RdE),
        .ImmExtE      (ImmExtE),
        .PCPlus4E     (PCPlus4E),
        .RegWriteE    (RegWriteE),
        .ResultSrcE   (ResultSrcE),
        .MemWriteE    (MemWriteE),
        .JumpE        (JumpE),
        .BranchE      (BranchE),
        .ALUControlE  (ALUControlE),
        .ALUSrcE      (ALUSrcE)
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
