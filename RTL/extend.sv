// Gerador de imediatos do estagio Decode.
// Ele apenas reorganiza os bits da instrucao; a futura control_unit decidira
// qual formato deve ser escolhido por meio de ImmSrcD.
module extend (
    input  logic [31:7] InstrD,
    input  logic [1:0]  ImmSrcD,
    output logic [31:0] ImmExtD
);

    // Codificacao de ImmSrcD usada no diagrama do datapath.
    // Como sao 2 bits, existem quatro escolhas: I, S, B e J.
    localparam logic [1:0] IMM_I = 2'b00;
    localparam logic [1:0] IMM_S = 2'b01;
    localparam logic [1:0] IMM_B = 2'b10;
    localparam logic [1:0] IMM_J = 2'b11;

    always_comb begin
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

            // Todos os valores de 2 bits ja aparecem acima. O default deixa
            // a saida conhecida mesmo diante de X durante uma simulacao.
            default: ImmExtD = 32'b0;
        endcase
    end

endmodule
