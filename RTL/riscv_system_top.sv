// Topo do sistema: conecta o core as memorias de instrucao e dados.
// O Register File recebe sua escrita exclusivamente do Writeback dentro do core.
module riscv_system_top #(
    parameter IMEM_INIT_FILE = ""
)(
    input  logic clk,
    input  logic reset
);

    // Ligacoes estruturais com MEM. A DMEM permanece desabilitada ate a LSU.
    logic [31:0] ReadDataM;
    logic [31:0] ALUResultM;
    logic [31:0] WriteDataM;
    logic        MemWriteM;

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

    // Saidas do registrador ID/EX, que alimentam o Execute.
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
    logic        JalrE;
    logic        BranchE;
    logic [3:0]  ALUControlE;
    logic        ALUSrcE;

    // Caminho combinacional do estagio Execute, antes do EX/MEM.
    logic [31:0] SrcAE;
    logic [31:0] WriteDataE;
    logic [31:0] SrcBE;
    logic [31:0] ALUResultE;
    logic        ZeroE;
    logic [31:0] PCTargetE;

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

    // O core recebe InstrF da memoria, devolve PCF como endereco da busca e
    // mantem internamente o pipeline completo ate a escrita no Register File.
    riscv_core u_riscv_core (
        .clk          (clk),
        .reset        (reset),
        .ReadDataM    (ReadDataM),
        .ALUResultM   (ALUResultM),
        .WriteDataM   (WriteDataM),
        .MemWriteM    (MemWriteM),
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
        .JalrE        (JalrE),
        .BranchE      (BranchE),
        .ALUControlE  (ALUControlE),
        .ALUSrcE      (ALUSrcE),
        .SrcAE        (SrcAE),
        .WriteDataE   (WriteDataE),
        .SrcBE        (SrcBE),
        .ALUResultE   (ALUResultE),
        .ZeroE        (ZeroE),
        .PCTargetE    (PCTargetE)
    );

    // Endereco e dado ja vem do EX/MEM. MemWriteM e zero para OP/OP-IMM e ainda
    // nao gera strobes: en/wstrb continuam inativos ate existir a futura LSU.
    // ReadDataM segue ao MEM/WB, mas LOAD exigira tratar a latencia sincrona.
    data_memory u_data_memory (
        .clk   (clk),
        .en    (1'b0),
        .addr  (ALUResultM),
        .wdata (WriteDataM),
        .wstrb (4'b0),
        .rdata (ReadDataM)
    );

endmodule
