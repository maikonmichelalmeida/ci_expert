// Nucleo do processador: agrupa datapath, control_unit e hazard_unit.
// As memorias ficam fora deste modulo, conforme a hierarquia do diagrama.
module riscv_core (
    input  logic clk,
    input  logic reset,
    input  logic [31:0] ReadDataM,
    output logic [31:0] ALUResultM,
    output logic [31:0] WriteDataM,
    output logic        MemWriteM,
    output logic [2:0]  StoreControlM,
    output logic [2:0]  LoadControlM,
    output logic        LoadAccessValidM,
    output logic        LoadEnableM,
    output logic [31:0] LoadDataM,
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
    output logic [2:0]  StoreControlE,
    output logic [2:0]  LoadControlE,
    output logic        JumpE,
    output logic        JalrE,
    output logic        BranchE,
    output logic [3:0]  ALUControlE,
    output logic        ALUSrcE,
    output logic        ALUASrcE,
    output logic [31:0] SrcAE,
    output logic [31:0] ALUOperandAE,
    output logic [31:0] WriteDataE,
    output logic [31:0] SrcBE,
    output logic [31:0] ALUResultE,
    output logic        ZeroE,
    output logic [31:0] PCTargetE
);

    // Controles do estagio Decode. A control_unit reconhece OP-IMM, OP, LOAD, STORE,
    // LUI, AUIPC, JAL, JALR e branches, com defaults seguros nos demais casos.
    logic       RegWriteD;
    logic [1:0] ResultSrcD;
    logic       MemWriteD;
    logic [2:0] StoreControlD;
    logic [2:0] LoadControlD;
    logic       JumpD;
    logic       JalrD;
    logic       BranchD;
    logic [2:0] BranchControlD;
    logic [3:0] ALUControlD;
    logic       ALUSrcD;
    logic       ALUASrcD;
    logic [2:0] ImmSrcD;

    // Sinais ja registrados em M/W e expostos ao forwarding sem duplicar estado.
    logic       RegWriteM;
    logic [4:0] RdM;
    logic       RegWriteW;
    logic [4:0] RdW;

    // ForwardAE/BE e os flushes de JAL/JALR sao funcionais nesta etapa. Os
    // stalls permanecem neutros ate o futuro tratamento de load-use.
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
        .ReadDataM    (ReadDataM),
        .ALUResultM   (ALUResultM),
        .WriteDataM   (WriteDataM),
        .MemWriteM    (MemWriteM),
        .StoreControlM(StoreControlM),
        .LoadControlM (LoadControlM),
        .LoadAccessValidM(LoadAccessValidM),
        .LoadEnableM  (LoadEnableM),
        .LoadDataM    (LoadDataM),
        .RegWriteM    (RegWriteM),
        .RdM          (RdM),
        .RegWriteW    (RegWriteW),
        .RdW          (RdW),
        .InstrF       (InstrF),
        .RegWriteD    (RegWriteD),
        .ResultSrcD   (ResultSrcD),
        .MemWriteD    (MemWriteD),
        .StoreControlD(StoreControlD),
        .LoadControlD (LoadControlD),
        .JumpD        (JumpD),
        .JalrD        (JalrD),
        .BranchD      (BranchD),
        .BranchControlD(BranchControlD),
        .ALUControlD  (ALUControlD),
        .ALUSrcD      (ALUSrcD),
        .ALUASrcD     (ALUASrcD),
        .ImmSrcD      (ImmSrcD),
        .StallF       (StallF),
        .StallD       (StallD),
        .FlushD       (FlushD),
        .FlushE       (FlushE),
        .ForwardAE    (ForwardAE),
        .ForwardBE    (ForwardBE),
        .PCSrcE       (PCSrcE),
        .PCTargetE    (PCTargetE),
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
        .StoreControlE(StoreControlE),
        .LoadControlE (LoadControlE),
        .JumpE        (JumpE),
        .JalrE        (JalrE),
        .BranchE      (BranchE),
        .ALUControlE  (ALUControlE),
        .ALUSrcE      (ALUSrcE),
        .ALUASrcE     (ALUASrcE),
        .SrcAE        (SrcAE),
        .ALUOperandAE (ALUOperandAE),
        .WriteDataE   (WriteDataE),
        .SrcBE        (SrcBE),
        .ALUResultE   (ALUResultE),
        .ZeroE        (ZeroE)
    );

    // O decoder combina OpD/funct e seus controles seguem com os dados da
    // instrucao pelos registradores de pipeline.
    control_unit u_control_unit (
        .clk         (clk),
        .reset       (reset),
        .OpD         (OpD),
        .Funct3D     (Funct3D),
        .Funct7b5D   (Funct7b5D),
        .RegWriteD   (RegWriteD),
        .ResultSrcD  (ResultSrcD),
        .MemWriteD   (MemWriteD),
        .StoreControlD(StoreControlD),
        .LoadControlD(LoadControlD),
        .JumpD       (JumpD),
        .JalrD       (JalrD),
        .BranchD     (BranchD),
        .BranchControlD(BranchControlD),
        .ALUControlD (ALUControlD),
        .ALUSrcD     (ALUSrcD),
        .ALUASrcD    (ALUASrcD),
        .ImmSrcD     (ImmSrcD)
    );

    // A hazard_unit compara as fontes em E com M/W e usa PCSrcE para limpar
    // as instrucoes mais jovens quando jump ou branch e resolvido no Execute.
    hazard_unit u_hazard_unit (
        .clk       (clk),
        .reset     (reset),
        .Rs1D      (Rs1D),
        .Rs2D      (Rs2D),
        .Rs1E      (Rs1E),
        .Rs2E      (Rs2E),
        .RdE       (RdE),
        .RdM       (RdM),
        .RegWriteM (RegWriteM),
        .RdW       (RdW),
        .RegWriteW (RegWriteW),
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
