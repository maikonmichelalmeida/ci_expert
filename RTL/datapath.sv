// Caminho de dados do core. Neste ponto do projeto ele reune PC, IF/ID,
// Decode, ID/EX, Execute e banco de registradores, preservando os nomes do diagrama.
module datapath (
    // ---------------- Sinais gerais do datapath ----------------
    input  logic clk,
    input  logic reset,

    // -------- Escrita temporaria no Register File --------
    input  logic [4:0]  rd_addr,
    input  logic [31:0] rd_data,
    input  logic        rd_we,

    // ---------------- Entrada do IF/ID ----------------
    // InstrF, PCF e PCPlus4F formam os dados que entram no grande
    // registrador IF/ID. PCF e PCPlus4F sao gerados dentro do datapath.
    input  logic [31:0] InstrF,

    // ---------------- Entradas do ID/EX ----------------
    // Estes controles com sufixo D atravessam juntos o grande registrador
    // ID/EX e aparecem no Execute com o mesmo nome terminado em E.
    input  logic        RegWriteD,
    input  logic [1:0]  ResultSrcD,
    input  logic        MemWriteD,
    input  logic        JumpD,
    input  logic        BranchD,
    input  logic [3:0]  ALUControlD,
    input  logic        ALUSrcD,
    input  logic [2:0]  ImmSrcD,

    // -------- Controle dos registradores de pipeline --------
    input  logic        StallF,
    input  logic        StallD,
    input  logic        FlushD,
    input  logic        FlushE,

    // -------- Controles reservados para forwarding --------
    input  logic [1:0]  ForwardAE,
    input  logic [1:0]  ForwardBE,

    // ---------------- Estagio Fetch (F) ----------------
    output logic        PCSrcE,
    output logic [31:0] PCTargetE,
    output logic [31:0] PCF,
    output logic [31:0] PCPlus4F,

    // ---------------- Saidas do IF/ID ----------------
    // InstrD, PCD e PCPlus4D formam, em conjunto, o conteudo armazenado
    // no grande registrador IF/ID mostrado no diagrama.
    output logic [31:0] InstrD,
    output logic [31:0] PCD,
    output logic [31:0] PCPlus4D,

    // ---------------- Estagio Decode (D) ----------------
    // Estes sinais sao produzidos em Decode e servem como dados de entrada
    // do grande registrador ID/EX.
    output logic [6:0]  OpD,
    output logic [4:0]  RdD,
    output logic [2:0]  Funct3D,
    output logic [4:0]  Rs1D,
    output logic [4:0]  Rs2D,
    output logic        Funct7b5D,
    output logic [31:0] RD1D,
    output logic [31:0] RD2D,
    output logic [31:0] ImmExtD,

    // ---------------- Saidas do ID/EX ----------------
    // Todos os sinais abaixo sao capturados juntos no clock e formam o
    // conteudo do grande registrador ID/EX mostrado no diagrama.
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
    output logic [3:0]  ALUControlE,
    output logic        ALUSrcE,

    // ---------------- Estagio Execute (E) ----------------
    output logic [31:0] SrcAE,
    output logic [31:0] WriteDataE,
    output logic [31:0] SrcBE,
    output logic [31:0] ALUResultE,
    output logic        ZeroE
);

    // Sinais ao redor do PC no diagrama: PCSrcE controla o mux, PCTargetE sera
    // o endereco alternativo e StallF sera o enable invertido do registrador PC.
    logic [31:0] PCNextF;
    logic        NegativeE;
    logic        CarryE;
    logic        OverflowE;

    // Branch e jump ainda nao sao funcionais. Zero sempre escolhe PCPlus4F.
    // StallF, por outro lado, ja vem da hazard_unit pela conexao definitiva.
    assign PCSrcE = 1'b0;

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

    // O Decode estrutural apenas separa os campos que ocupam posicoes fixas
    // em InstrD. Nenhum opcode ou funct e interpretado nesta etapa.
    assign OpD       = InstrD[6:0];
    assign RdD       = InstrD[11:7];
    assign Funct3D   = InstrD[14:12];
    assign Rs1D      = InstrD[19:15];
    assign Rs2D      = InstrD[24:20];
    assign Funct7b5D = InstrD[30];

    // Rs1D, Rs2D e RdD sao somente recortes dos bits da instrucao. Em formatos
    // que nao usam algum desses campos, os bits ainda sao extraidos, mas a
    // futura control_unit devera ignora-los. Em ADDI, por exemplo, InstrD[24:20]
    // pertence ao imediato mesmo que o fio Rs2D continue mostrando esses bits.

    // O Extend recebe somente os bits que podem formar um imediato. ImmSrcD
    // nao identifica a instrucao: ele apenas escolhe como reorganizar os bits.
    extend u_extend (
        .InstrD  (InstrD[31:7]),
        .ImmSrcD (ImmSrcD),
        .ImmExtD (ImmExtD)
    );

    // A leitura vem da instrucao real: Rs1D e Rs2D escolhem os dois
    // registradores, e seus conteudos aparecem no diagrama como RD1D e RD2D.
    // A escrita ainda usa o caminho externo temporario ate existir Writeback.
    register_file u_register_file (
        .clk      (clk),
        .rs1_addr (Rs1D),
        .rs2_addr (Rs2D),
        .rd_addr  (rd_addr),
        .rd_data  (rd_data),
        .rd_we    (rd_we),
        .rs1_data (RD1D),
        .rs2_data (RD2D)
    );

    always_ff @(posedge clk) begin
        // Reset ou FlushE insere uma bolha segura no Execute. Todos os enables
        // de escrita ficam em zero, assim como os dados observaveis.
        if (reset || FlushE) begin
            RD1E        <= 32'b0;
            RD2E        <= 32'b0;
            PCE         <= 32'b0;
            Rs1E        <= 5'b0;
            Rs2E        <= 5'b0;
            RdE         <= 5'b0;
            ImmExtE     <= 32'b0;
            PCPlus4E    <= 32'b0;
            RegWriteE   <= 1'b0;
            ResultSrcE  <= 2'b00;
            MemWriteE   <= 1'b0;
            JumpE       <= 1'b0;
            BranchE     <= 1'b0;
            ALUControlE <= 4'b0000;
            ALUSrcE     <= 1'b0;
        end else begin
            RD1E        <= RD1D;
            RD2E        <= RD2D;
            PCE         <= PCD;
            Rs1E        <= Rs1D;
            Rs2E        <= Rs2D;
            RdE         <= RdD;
            ImmExtE     <= ImmExtD;
            PCPlus4E    <= PCPlus4D;
            RegWriteE   <= RegWriteD;
            ResultSrcE  <= ResultSrcD;
            MemWriteE   <= MemWriteD;
            JumpE       <= JumpD;
            BranchE     <= BranchD;
            ALUControlE <= ALUControlD;
            ALUSrcE     <= ALUSrcD;
        end
    end

    // Caminho normal provisoriamente selecionado pelos futuros muxes de
    // forwarding. Isto nao remove nem altera a arquitetura desses muxes:
    // ForwardAE e ForwardBE continuam chegando ao datapath e, quando existirem
    // ALUResultM e ResultW, selecionarao tambem essas fontes como no diagrama.
    assign SrcAE      = RD1E;
    assign WriteDataE = RD2E;

    // ALUSrcE forma o mux da segunda entrada da ALU. Zero usa o segundo dado
    // do Register File; um usa o imediato ja registrado no ID/EX.
    assign SrcBE = ALUSrcE ? ImmExtE : WriteDataE;

    // O somador de alvo ja ocupa seu lugar no Execute, mas PCSrcE permanece
    // zero. Portanto PCTargetE ainda nao redireciona o PC nesta etapa.
    assign PCTargetE = PCE + ImmExtE;

    // A ALU agora pertence ao caminho real do pipeline. ALUControlE possui os
    // mesmos 4 bits de alu_op, sem decoder intermediario ou ajuste de largura.
    alu u_alu (
        .a        (SrcAE),
        .b        (SrcBE),
        .alu_op   (ALUControlE),
        .result   (ALUResultE),
        .zero     (ZeroE),
        .negative (NegativeE),
        .carry    (CarryE),
        .overflow (OverflowE)
    );

    // NegativeE, CarryE e OverflowE preservam as demais flags da ALU. Ainda
    // nao existe logica do pipeline que as consuma; somente ZeroE aparece no
    // caminho de branch previsto pelo diagrama atual.

endmodule
