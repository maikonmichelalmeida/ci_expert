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
    output logic [31:0] RD2D,
    output logic [31:0] ImmExtD,
    output logic [31:0] RD1E,
    output logic [31:0] RD2E,
    output logic [31:0] PCE,
    output logic [4:0]  Rs1E,
    output logic [4:0]  Rs2E,
    output logic [4:0]  RdE,
    output logic [31:0] ImmExtE,
    output logic [31:0] PCPlus4E,
    output logic        RegWriteE,
    output logic [1:0]  ResultSrcE,
    output logic        MemWriteE,
    output logic        JumpE,
    output logic        BranchE,
    output logic [2:0]  ALUControlE,
    output logic        ALUSrcE
);

    // Controles do estagio Decode. A control_unit ja dirige os fios definitivos,
    // mas nesta etapa seus valores continuam fixos e seguros.
    logic       RegWriteD;
    logic [1:0] ResultSrcD;
    logic       MemWriteD;
    logic       JumpD;
    logic       BranchD;
    logic [2:0] ALUControlD;
    logic       ALUSrcD;
    logic [1:0] ImmSrcD;

    // Saidas estruturais da hazard_unit. StallF chega ao PC, StallD e FlushD
    // chegam ao IF/ID, e FlushE chega ao ID/EX. As selecoes de forwarding ja
    // possuem os nomes do diagrama, mas ainda nao comandam muxes funcionais.
    logic       StallF;
    logic       StallD;
    logic       FlushD;
    logic       FlushE;
    logic [1:0] ForwardAE;
    logic [1:0] ForwardBE;
    logic       PCSrcE;

    // A instrucao vem da IMEM externa. O datapath contem os registradores de
    // pipeline e recebe por fios os controles produzidos pelos outros blocos.
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
        .RegWriteD    (RegWriteD),
        .ResultSrcD   (ResultSrcD),
        .MemWriteD    (MemWriteD),
        .JumpD        (JumpD),
        .BranchD      (BranchD),
        .ALUControlD  (ALUControlD),
        .ALUSrcD      (ALUSrcD),
        .ImmSrcD      (ImmSrcD),
        .StallF       (StallF),
        .StallD       (StallD),
        .FlushD       (FlushD),
        .FlushE       (FlushE),
        .ForwardAE    (ForwardAE),
        .ForwardBE    (ForwardBE),
        .PCSrcE       (PCSrcE),
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

    // O decoder ainda nao interpreta nenhuma instrucao. Esta conexao apenas
    // posiciona OpD/funct como entradas e os controles D como saidas.
    control_unit u_control_unit (
        .clk         (clk),
        .reset       (reset),
        .OpD         (OpD),
        .Funct3D     (Funct3D),
        .Funct7b5D   (Funct7b5D),
        .RegWriteD   (RegWriteD),
        .ResultSrcD  (ResultSrcD),
        .MemWriteD   (MemWriteD),
        .JumpD       (JumpD),
        .BranchD     (BranchD),
        .ALUControlD (ALUControlD),
        .ALUSrcD     (ALUSrcD),
        .ImmSrcD     (ImmSrcD)
    );

    // A hazard_unit e a unica origem destes sinais. Por enquanto ela fornece
    // apenas valores neutros, sem detectar dependencias ou fazer forwarding.
    hazard_unit u_hazard_unit (
        .clk       (clk),
        .reset     (reset),
        .Rs1D      (Rs1D),
        .Rs2D      (Rs2D),
        .Rs1E      (Rs1E),
        .Rs2E      (Rs2E),
        .RdE       (RdE),
        .PCSrcE    (PCSrcE),
        .ResultSrcE(ResultSrcE),
        .StallF    (StallF),
        .StallD    (StallD),
        .FlushD    (FlushD),
        .FlushE    (FlushE),
        .ForwardAE (ForwardAE),
        .ForwardBE (ForwardBE)
    );

endmodule
