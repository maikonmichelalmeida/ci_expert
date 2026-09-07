// Decodificacao de OP-IMM, OP e JAL do RV32I.
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
    output logic       JumpD,
    output logic       BranchD,
    output logic [3:0] ALUControlD,
    output logic       ALUSrcD,
    output logic [2:0] ImmSrcD
);

    always_comb begin
        // Uma instrucao ainda nao suportada atravessa como uma bolha:
        // pode produzir dados internos, mas nao escreve registradores ou memoria.
        RegWriteD   = 1'b0;
        ResultSrcD  = 2'b00;
        MemWriteD   = 1'b0;
        JumpD       = 1'b0;
        BranchD     = 1'b0;
        ALUControlD = 4'b0000;
        ALUSrcD     = 1'b0;
        ImmSrcD     = 3'b000;

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
                7'b1101111: begin // JAL: grava PC+4 e salta para PC+imediato J.
                    RegWriteD  = 1'b1;
                    ResultSrcD = 2'b10;
                    JumpD      = 1'b1;
                    ALUControlD = 4'b0000;
                    ALUSrcD    = 1'b0;
                    ImmSrcD    = 3'b011;
                end
                default: begin
                    // Outros opcodes conservam os defaults sem efeitos de escrita.
                end
            endcase
        end
    end

    // O Extend continua fazendo extensao de sinal inclusive em SLTIU:
    // imediato -1 chega como 0xffffffff antes da comparacao unsigned.
    // Nos shifts, a ALU usa somente B[4:0]; em OP, B recebe RD2E e, em OP-IMM,
    // recebe ImmExtE. Nao precisamos de outro caminho para o shift amount.
    // O target de JAL nao usa a ALU: PCE + ImmExtE possui um somador proprio
    // ja previsto no datapath. A ALU recebe controles neutros nessa instrucao.
    // O decoder recebe somente InstrD[30]. Assim, reconhece as codificacoes
    // RV32I usadas aqui, mas ainda nao valida todos os sete bits de funct7,
    // nao implementa a extensao M e nao gera trap de instrucao ilegal.

    // clk permanece na interface existente. O controle e combinacional,
    // sem estado interno; reset apenas mantem os comandos inativos.

endmodule
