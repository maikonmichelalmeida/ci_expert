// Caminho de dados IF -> ID -> EX -> MEM -> WB, com os nomes do diagrama.
// As quatro fronteiras guardam dados e controles da mesma instrucao no clock.
module datapath (
    // ---------------- Sinais gerais do datapath ----------------
    input  logic clk,
    input  logic reset,

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

    // Selecao do Extend em Decode; o ID/EX transporta ImmExtD, nao ImmSrcD.
    input  logic [2:0]  ImmSrcD,

    // -------- Controle dos registradores de pipeline --------
    input  logic        StallF,
    input  logic        StallD,
    input  logic        FlushD,
    input  logic        FlushE,

    // ---------------- Controles dos muxes de forwarding ----------------
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
    // Campos para a control_unit e dados para o ID/EX. OpD e Funct3D, por
    // exemplo, sao usados em Decode e nao precisam atravessar essa fronteira.
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
    output logic        ZeroE,

    // -------- EX/MEM PIPELINE REGISTER: saidas para a DMEM --------
    output logic [31:0] ALUResultM,
    output logic [31:0] WriteDataM,
    output logic        MemWriteM,
    output logic        RegWriteM,
    output logic [4:0]  RdM,

    // -------- MEM/WB PIPELINE REGISTER: sinais para forwarding --------
    output logic        RegWriteW,
    output logic [4:0]  RdW,

    // ---------------- Entrada do estagio MEM ----------------
    // A DMEM continua sincrona. Este fio prepara o caminho de dados de leitura,
    // mas LOAD ainda depende do tratamento correto dessa latencia no futuro.
    input  logic [31:0] ReadDataM
);

    // -------- EX/MEM PIPELINE REGISTER: demais campos --------
    // Junto de ALUResultM, WriteDataM e MemWriteM, estes sinais formam
    // o grande registrador EX/MEM. Exemplo: resultado 1 e Rd=1 seguem juntos.
    logic [1:0]  ResultSrcM;
    logic [31:0] PCPlus4M;

    // ---------------- MEM/WB PIPELINE REGISTER ----------------
    // Resultado, destino e enable chegam juntos ao ultimo estagio.
    // RegWriteW=1 e RdW=1 autorizam gravar ResultW em x1 no proximo posedge.
    logic [1:0]  ResultSrcW;
    logic [31:0] ALUResultW;
    logic [31:0] ReadDataW;
    logic [31:0] PCPlus4W;

    // ---------------- Estagio Writeback (W) ----------------
    logic [31:0] ResultW;

    // Sinais ao redor do PC no diagrama: PCSrcE controla o mux, PCTargetE sera
    // o endereco alternativo e StallF sera o enable invertido do registrador PC.
    logic [31:0] PCNextF;
    logic        NegativeE;
    logic        CarryE;
    logic        OverflowE;

    // JAL e resolvido no Execute. JumpE seleciona PCTargetE no mux do PC;
    // branches continuam inativos porque ainda nao entram nesta expressao.
    assign PCSrcE = JumpE;

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
    // em InstrD. A interpretacao de opcode/funct fica na control_unit.
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
    // O unico escritor agora e o WB: destino RdW e dado ResultW.
    // O bloqueio por reset impede gravar um WB pendente no proprio flanco
    // que limpa o pipeline, antes das atribuicoes nao bloqueantes atualizarem W.
    register_file u_register_file (
        .clk      (clk),
        .rs1_addr (Rs1D),
        .rs2_addr (Rs2D),
        .rd_addr  (RdW),
        .rd_data  (ResultW),
        .rd_we    (RegWriteW && !reset),
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

    // Os muxes escolhem o valor original (00), o WB (01) ou o resultado mais
    // recente no EX/MEM (10). O codigo 11 e reservado e volta ao valor original.
    always_comb begin
        SrcAE = RD1E;
        case (ForwardAE)
            2'b00: SrcAE = RD1E;
            2'b01: SrcAE = ResultW;
            2'b10: SrcAE = ALUResultM;
            default: SrcAE = RD1E;
        endcase
    end

    always_comb begin
        WriteDataE = RD2E;
        case (ForwardBE)
            2'b00: WriteDataE = RD2E;
            2'b01: WriteDataE = ResultW;
            2'b10: WriteDataE = ALUResultM;
            default: WriteDataE = RD2E;
        endcase
    end

    // ForwardBE atua antes deste mux. Assim STORE podera usar WriteDataE e uma
    // OP-IMM continua usando ImmExtE na ALU, mesmo se ForwardBE estiver ativo.
    assign SrcBE = ALUSrcE ? ImmExtE : WriteDataE;

    // JAL usa exatamente o somador PC-relative previsto no diagrama.
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

    always_ff @(posedge clk) begin
        if (reset) begin
            RegWriteM  <= 1'b0;
            ResultSrcM <= 2'b00;
            MemWriteM  <= 1'b0;
            ALUResultM <= 32'b0;
            WriteDataM <= 32'b0;
            RdM        <= 5'b0;
            PCPlus4M   <= 32'b0;
        end else begin
            RegWriteM  <= RegWriteE;
            ResultSrcM <= ResultSrcE;
            MemWriteM  <= MemWriteE;
            ALUResultM <= ALUResultE;
            WriteDataM <= WriteDataE;
            RdM        <= RdE;
            PCPlus4M   <= PCPlus4E;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            RegWriteW  <= 1'b0;
            ResultSrcW <= 2'b00;
            ALUResultW <= 32'b0;
            ReadDataW  <= 32'b0;
            RdW        <= 5'b0;
            PCPlus4W   <= 32'b0;
        end else begin
            RegWriteW  <= RegWriteM;
            ResultSrcW <= ResultSrcM;
            ALUResultW <= ALUResultM;
            // Captura a saida atual da DMEM sem mudar seu timing. Para OP e
            // OP-IMM ela nao e usada; esta conexao ainda nao executa LOAD.
            ReadDataW  <= ReadDataM;
            RdW        <= RdM;
            PCPlus4W   <= PCPlus4M;
        end
    end

    // Mux final do diagrama: 00 retorna a ALU, 01 a memoria e 10 o PC+4.
    // OP/OP-IMM escolhem 00 e JAL escolhe 10 para gravar PC+4 em rd.
    // A entrada 01 permanece preparada para LOAD; 11 devolve zero.
    always_comb begin
        ResultW = 32'b0;
        case (ResultSrcW)
            2'b00: ResultW = ALUResultW;
            2'b01: ResultW = ReadDataW;
            2'b10: ResultW = PCPlus4W;
            default: ResultW = 32'b0;
        endcase
    end

endmodule
