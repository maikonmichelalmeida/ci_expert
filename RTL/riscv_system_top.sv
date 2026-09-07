// Topo do sistema: conecta o core as memorias de instrucao e dados.
// O Register File recebe sua escrita exclusivamente do Writeback dentro do core.
module riscv_system_top #(
    parameter IMEM_INIT_FILE = ""
)(
    input  logic clk,
    input  logic reset
);

    // Ligacoes estruturais com MEM. STORE usa os sinais classicos do EX/MEM;
    // LOAD continua pendente e ReadDataM ainda nao produz resultado funcional.
    logic [31:0] ReadDataM;
    logic [31:0] ALUResultM;
    logic [31:0] WriteDataM;
    logic        MemWriteM;
    logic [2:0]  StoreControlM;
    logic [31:0] StoreDataM;
    logic [3:0]  StoreWStrbM;
    logic        StoreEnableM;
    logic [4:0]  StoreShiftAmountM;

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
    logic [2:0]  StoreControlE;
    logic        JumpE;
    logic        JalrE;
    logic        BranchE;
    logic [3:0]  ALUControlE;
    logic        ALUSrcE;
    logic        ALUASrcE;

    // Caminho combinacional do estagio Execute, antes do EX/MEM.
    logic [31:0] SrcAE;
    logic [31:0] ALUOperandAE;
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
        .StoreControlM(StoreControlM),
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
        .StoreControlE(StoreControlE),
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
        .ZeroE        (ZeroE),
        .PCTargetE    (PCTargetE)
    );

    // Cada unidade em ALUResultM[1:0] representa um byte dentro da palavra.
    // A concatenacao converte 0/1/2/3 em deslocamentos de 0/8/16/24 bits sem
    // usar multiplicador: por exemplo, 2'b10 vira 5'b10000, isto e, 16.
    assign StoreShiftAmountM = {ALUResultM[1:0], 3'b000};

    // Pequeno adaptador entre o pipeline e os quatro byte lanes da DMEM.
    // WriteDataM continua sendo o rs2 integral do diagrama; somente StoreDataM
    // desloca os bytes ate as lanes fisicas selecionadas por StoreWStrbM.
    always_comb begin
        StoreDataM   = 32'b0;
        StoreWStrbM  = 4'b0000;
        StoreEnableM = 1'b0;

        if (MemWriteM) begin
            case (StoreControlM)
                3'b000: begin // SB aceita qualquer byte da palavra.
                    StoreDataM   = WriteDataM << StoreShiftAmountM;
                    StoreWStrbM  = 4'b0001 << ALUResultM[1:0];
                    StoreEnableM = 1'b1;
                end
                3'b001: begin // SH aceita somente enderecos pares.
                    if (ALUResultM[0] == 1'b0) begin
                        StoreDataM   = WriteDataM << StoreShiftAmountM;
                        StoreWStrbM  = 4'b0011 << ALUResultM[1:0];
                        StoreEnableM = 1'b1;
                    end
                end
                3'b010: begin // SW aceita somente multiplos de quatro.
                    if (ALUResultM[1:0] == 2'b00) begin
                        StoreDataM   = WriteDataM;
                        StoreWStrbM  = 4'b1111;
                        StoreEnableM = 1'b1;
                    end
                end
                default: begin
                    // Misaligned store exception ainda nao existe. Tipos
                    // reservados e SH/SW desalinhados sao suprimidos acima.
                end
            endcase
        end
    end

    // A DMEM continua generica: recebe endereco, dado alinhado e byte enables,
    // sem conhecer opcode ou funct3. Sua escrita permanece no posedge.
    // LOAD ainda exigira generalizar o enable e tratar a leitura sincrona.
    data_memory u_data_memory (
        .clk   (clk),
        .en    (StoreEnableM),
        .addr  (ALUResultM),
        .wdata (StoreDataM),
        .wstrb (StoreWStrbM),
        .rdata (ReadDataM)
    );

endmodule
