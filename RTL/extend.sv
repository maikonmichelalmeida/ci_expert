// Gerador de imediatos do estagio Decode.
// Ele apenas reorganiza os bits da instrucao; a futura control_unit decidira
// qual formato deve ser escolhido por meio de ImmSrcD.
module extend (
    input  logic [31:7] InstrD,
    input  logic [2:0]  ImmSrcD,
    output logic [31:0] ImmExtD
);

    // Codificacao explicita de ImmSrcD. Os 3 bits acomodam os cinco formatos
    // usados pelo RV32I e deixam 101, 110 e 111 reservados para uso futuro.
    localparam logic [2:0] IMM_I = 3'b000;
    localparam logic [2:0] IMM_S = 3'b001;
    localparam logic [2:0] IMM_B = 3'b010;
    localparam logic [2:0] IMM_J = 3'b011;
    localparam logic [2:0] IMM_U = 3'b100;

    always_comb begin
        // O valor inicial garante uma saida segura e evita latch mesmo se
        // ImmSrcD receber uma codificacao reservada ou desconhecida.
        ImmExtD = 32'b0;

        // Nao usamos unique porque os codigos reservados sao entradas validas
        // para cair no default durante verificacoes estruturais.
        case (ImmSrcD)
            // Formato I: o imediato ocupa InstrD[31:20]. Repetir o bit 31
            // vinte vezes faz a extensao de sinal de 12 para 32 bits.
            IMM_I: ImmExtD = {{20{InstrD[31]}}, InstrD[31:20]};

            // Formato S: o imediato foi dividido em duas partes pela posicao
            // de rs2 e rs1. Aqui elas voltam a formar imm[11:0].
            IMM_S: ImmExtD = {{20{InstrD[31]}}, InstrD[31:25],
                              InstrD[11:7]};

            // Formato B: os bits sao remontados na ordem do offset de branch.
            // O zero final representa alinhamento de 2 bytes. Exemplo: os
            // bits que codificam 8 produzem ImmExtD = 32'h0000_0008.
            IMM_B: ImmExtD = {{19{InstrD[31]}}, InstrD[31], InstrD[7],
                              InstrD[30:25], InstrD[11:8], 1'b0};

            // Formato J: tambem possui zero implicito no bit menos
            // significativo e recebe extensao de sinal ate 32 bits.
            IMM_J: ImmExtD = {{11{InstrD[31]}}, InstrD[31], InstrD[19:12],
                              InstrD[20], InstrD[30:21], 1'b0};

            // Formato U: os 20 bits superiores da instrucao permanecem nas
            // mesmas posicoes e os 12 bits inferiores recebem zero.
            // Exemplo: InstrD[31:12] = 20'h12345 produz 32'h1234_5000.
            IMM_U: ImmExtD = {InstrD[31:12], 12'b0};

            // Codificacoes reservadas e valores desconhecidos produzem zero.
            default: ImmExtD = 32'b0;
        endcase
    end

endmodule
