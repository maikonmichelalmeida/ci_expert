// Decodificacao de OP-IMM, OP, LOAD, STORE, LUI, AUIPC, JAL, JALR e branches.
// E como se fosse o bloco que le opcode/funct e distribui comandos para ALU,
// banco de registradores, memorias e registradores de pipeline.
module control_unit (
    input  logic       clk,
    input  logic       reset,
    input  logic [6:0] OpD,
    input  logic [2:0] Funct3D,
    input  logic       Funct7b5D,
    output logic       RegWriteD,
    output logic [1:0] ResultSrcD,
    output logic       MemWriteD,
    output logic [2:0] StoreControlD,
    output logic [2:0] LoadControlD,
    output logic       JumpD,
    output logic       JalrD,
    output logic       BranchD,
    output logic [2:0] BranchControlD,
    output logic [3:0] ALUControlD,
    output logic       ALUSrcD,
    output logic       ALUASrcD,
    output logic [2:0] ImmSrcD,
    output logic       UsesRs1D,
    output logic       UsesRs2D
);

    always_comb begin
        // Uma instrucao ainda nao suportada atravessa como uma bolha:
        // pode produzir dados internos, mas nao escreve registradores ou memoria.
        RegWriteD   = 1'b0;
        ResultSrcD  = 2'b00;
        MemWriteD   = 1'b0;
        StoreControlD = 3'b000;
        LoadControlD  = 3'b000;
        JumpD       = 1'b0;
        JalrD       = 1'b0;
        BranchD     = 1'b0;
        BranchControlD = 3'b000;
        ALUControlD = 4'b0000;
        ALUSrcD     = 1'b0;
        ALUASrcD    = 1'b0;
        ImmSrcD     = 3'b000;
        UsesRs1D    = 1'b0;
        UsesRs2D    = 1'b0;

        if (!reset) begin
            case (OpD)
                7'b0010011: begin // OP-IMM: rs1 e imediato I -> ALU -> WB.
                    RegWriteD = 1'b1;
                    ALUSrcD   = 1'b1;
                    case (Funct3D)
                        3'b000: ALUControlD = 4'b0000; // ADDI
                        3'b010: ALUControlD = 4'b0101; // SLTI, signed
                        3'b011: ALUControlD = 4'b0110; // SLTIU, unsigned
                        3'b100: ALUControlD = 4'b0100; // XORI
                        3'b110: ALUControlD = 4'b0011; // ORI
                        3'b111: ALUControlD = 4'b0010; // ANDI
                        3'b001: begin // SLLI exige bit 30 igual a zero.
                            if (Funct7b5D == 1'b0) begin
                                ALUControlD = 4'b0111;
                            end else begin
                                RegWriteD = 1'b0;
                                ALUSrcD   = 1'b0;
                            end
                        end
                        3'b101: begin
                            case (Funct7b5D)
                                1'b0: ALUControlD = 4'b1000; // SRLI
                                1'b1: ALUControlD = 4'b1001; // SRAI
                                default: begin
                                    RegWriteD = 1'b0;
                                    ALUSrcD   = 1'b0;
                                end
                            endcase
                        end
                        default: begin
                            RegWriteD = 1'b0;
                            ALUSrcD   = 1'b0;
                        end
                    endcase
                end
                7'b0110011: begin // OP: rs1 e rs2 -> ALU -> WB.
                    RegWriteD = 1'b1;
                    ALUSrcD   = 1'b0;
                    case (Funct3D)
                        3'b000: begin
                            case (Funct7b5D)
                                1'b0: ALUControlD = 4'b0000; // ADD
                                1'b1: ALUControlD = 4'b0001; // SUB
                                default: RegWriteD = 1'b0;
                            endcase
                        end
                        3'b001: begin // SLL da base RV32I exige bit 30 igual a zero.
                            if (Funct7b5D == 1'b0)
                                ALUControlD = 4'b0111;
                            else
                                RegWriteD = 1'b0;
                        end
                        3'b010: begin // SLT, comparacao signed.
                            if (Funct7b5D == 1'b0)
                                ALUControlD = 4'b0101;
                            else
                                RegWriteD = 1'b0;
                        end
                        3'b011: begin // SLTU, comparacao unsigned.
                            if (Funct7b5D == 1'b0)
                                ALUControlD = 4'b0110;
                            else
                                RegWriteD = 1'b0;
                        end
                        3'b100: begin // XOR.
                            if (Funct7b5D == 1'b0)
                                ALUControlD = 4'b0100;
                            else
                                RegWriteD = 1'b0;
                        end
                        3'b101: begin
                            case (Funct7b5D)
                                1'b0: ALUControlD = 4'b1000; // SRL
                                1'b1: ALUControlD = 4'b1001; // SRA
                                default: RegWriteD = 1'b0;
                            endcase
                        end
                        3'b110: begin // OR.
                            if (Funct7b5D == 1'b0)
                                ALUControlD = 4'b0011;
                            else
                                RegWriteD = 1'b0;
                        end
                        3'b111: begin // AND.
                            if (Funct7b5D == 1'b0)
                                ALUControlD = 4'b0010;
                            else
                                RegWriteD = 1'b0;
                        end
                        default: RegWriteD = 1'b0;
                    endcase
                end
                7'b0000011: begin // LOAD: rs1+imediato I forma o endereco.
                    case (Funct3D)
                        3'b000, // LB
                        3'b001, // LH
                        3'b010, // LW
                        3'b100, // LBU
                        3'b101: begin // LHU
                            RegWriteD    = 1'b1;
                            ResultSrcD   = 2'b01;
                            LoadControlD = Funct3D;
                            ALUControlD  = 4'b0000; // ADD
                            ALUSrcD      = 1'b1;
                            ALUASrcD     = 1'b0;
                            ImmSrcD      = 3'b000;  // Imediato I-type.
                        end
                        default: begin
                            // funct3 011, 110 e 111 nao representam LOAD RV32I.
                            // Sem traps, atravessam sem acesso ou escrita em rd.
                        end
                    endcase
                end
                7'b0100011: begin // STORE: rs1+imediato S forma o endereco.
                    case (Funct3D)
                        3'b000, // SB
                        3'b001, // SH
                        3'b010: begin // SW
                            MemWriteD     = 1'b1;
                            StoreControlD = Funct3D;
                            ALUControlD   = 4'b0000; // ADD
                            ALUSrcD       = 1'b1;
                            ALUASrcD      = 1'b0;
                            ImmSrcD       = 3'b001;  // Imediato S-type.
                        end
                        default: begin
                            // Os demais funct3 de STORE sao reservados. Sem
                            // traps, atravessam sem escrita na memoria.
                        end
                    endcase
                end
                7'b0110111: begin // LUI: imediato U passa pela ALU ate WB.
                    RegWriteD   = 1'b1;
                    ResultSrcD  = 2'b00;
                    ALUControlD = 4'b1010; // PASS_B
                    ALUSrcD     = 1'b1;
                    ALUASrcD    = 1'b0;    // Entrada A e ignorada por PASS_B.
                    ImmSrcD     = 3'b100;
                end
                7'b0010111: begin // AUIPC: PC da instrucao + imediato U.
                    RegWriteD   = 1'b1;
                    ResultSrcD  = 2'b00;
                    ALUControlD = 4'b0000; // ADD
                    ALUSrcD     = 1'b1;
                    ALUASrcD    = 1'b1;    // Seleciona PCE na entrada A.
                    ImmSrcD     = 3'b100;
                end
                7'b1101111: begin // JAL: grava PC+4 e salta para PC+imediato J.
                    RegWriteD  = 1'b1;
                    ResultSrcD = 2'b10;
                    JumpD      = 1'b1;
                    JalrD      = 1'b0;
                    ALUControlD = 4'b0000;
                    ALUSrcD    = 1'b0;
                    ImmSrcD    = 3'b011;
                end
                7'b1100111: begin // JALR valido somente quando funct3=000.
                    if (Funct3D == 3'b000) begin
                        RegWriteD   = 1'b1;
                        ResultSrcD  = 2'b10;
                        JumpD       = 1'b1;
                        JalrD       = 1'b1;
                        ALUControlD = 4'b0000;
                        ALUSrcD     = 1'b1;
                        ImmSrcD     = 3'b000;
                    end
                end
                7'b1100011: begin // BRANCH: compara rs1 e rs2 no Execute.
                    case (Funct3D)
                        3'b000, // BEQ
                        3'b001, // BNE
                        3'b100, // BLT
                        3'b101, // BGE
                        3'b110, // BLTU
                        3'b111: begin // BGEU
                            BranchD        = 1'b1;
                            BranchControlD = Funct3D;
                            ALUControlD    = 4'b0001; // SUB preserva ZeroE.
                            ALUSrcD        = 1'b0;
                            ImmSrcD        = 3'b010;  // Imediato B-type.
                        end
                        default: begin
                            // funct3 010 e 011 sao reservados. Sem suporte a
                            // traps, atravessam como uma bolha sem redirect.
                        end
                    endcase
                end
                default: begin
                    // Outros opcodes conservam os defaults sem efeitos de escrita.
                end
            endcase

            // InstrD sempre possui bits nas posicoes de rs1/rs2, mas nem todo
            // formato usa esses campos. Os sinais abaixo descrevem somente as
            // fontes arquiteturais de uma instrucao que o decoder julgou valida.
            case (OpD)
                7'b0110011: begin // OP
                    UsesRs1D = RegWriteD;
                    UsesRs2D = RegWriteD;
                end
                7'b0010011: UsesRs1D = RegWriteD; // OP-IMM
                7'b0000011: UsesRs1D = RegWriteD &&
                                        (ResultSrcD == 2'b01); // LOAD
                7'b0100011: begin // STORE
                    UsesRs1D = MemWriteD;
                    UsesRs2D = MemWriteD;
                end
                7'b1100011: begin // BRANCH
                    UsesRs1D = BranchD;
                    UsesRs2D = BranchD;
                end
                7'b1100111: UsesRs1D = JalrD; // JALR
                default: begin
                    // LUI, AUIPC, JAL e instrucoes invalidas nao usam os
                    // campos rs1/rs2, mesmo que seus bits coincidam com RdE.
                end
            endcase
        end
    end

    // O Extend continua fazendo extensao de sinal inclusive em SLTIU:
    // imediato -1 chega como 0xffffffff antes da comparacao unsigned.
    // Nos shifts, a ALU usa somente B[4:0]; em OP, B recebe RD2E e, em OP-IMM,
    // recebe ImmExtE. Nao precisamos de outro caminho para o shift amount.
    // LUI usa PASS_B e AUIPC usa ADD com PCE na entrada A. Ambos mantem
    // ResultSrcD=00 para seguir pelo caminho normal ALU -> M -> W.
    // STORE usa a mesma ALU para rs1+imediato S e conserva rs2 separado em
    // WriteDataE; StoreControlD informa ao estagio MEM se e SB, SH ou SW.
    // LOAD tambem usa a ALU normal para rs1+imediato I. ResultSrcD=01 escolhe
    // a memoria no WB e LoadControlD conserva o proprio funct3 ate MEM.
    // JAL e branch usam o somador PCE+ImmExtE. JALR configura a ALU como ADD
    // para formar SrcAE+ImmExtE; JalrE escolhe qual target alimenta o PC.
    // O decoder recebe somente InstrD[30]. Assim, reconhece as codificacoes
    // RV32I usadas aqui, mas ainda nao valida todos os sete bits de funct7,
    // nao implementa a extensao M e nao gera trap de instrucao ilegal.

    // clk permanece na interface existente. O controle e combinacional,
    // sem estado interno; reset apenas mantem os comandos inativos.

endmodule
