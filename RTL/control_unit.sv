// Decodificacao minima do processador: neste checkpoint reconhece apenas ADDI.
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

        // ADDI soma rs1 ao imediato I e leva a saida da ALU ate o Writeback.
        // Exemplo: 00100093 e addi x1,x0,1. O bit Funct7b5D pertence ao
        // imediato neste formato; ele nao restringe o reconhecimento de ADDI.
        if (!reset && (OpD == 7'b0010011) && (Funct3D == 3'b000)) begin
            RegWriteD = 1'b1;
            ALUSrcD   = 1'b1;
        end
    end

    // clk permanece na interface existente. O controle e combinacional,
    // sem estado interno; reset apenas mantem os comandos inativos.

endmodule
