// Unidade Logica e Aritmetica de 32 bits do datapath.
// alu_op funciona como a selecao de um mux: cada codigo escolhe uma operacao
// e coloca o resultado correspondente na mesma saida result.
module alu (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [3:0]  alu_op,
    output logic [31:0] result,
    output logic        zero,
    output logic        negative,
    output logic        carry,
    output logic        overflow
);

    // O bit extra guarda o vai-um das operacoes aritmeticas.
    // Exemplo: 0xffff_ffff + 1 produz 33'h1_0000_0000; os 32 bits baixos
    // formam result=0 e o bit 32 forma carry=1.
    logic [32:0] arithmetic_result;

    // always_comb recalcula as saidas sempre que uma entrada muda.
    // Os valores iniciais cobrem todas as saidas e evitam a inferencia de
    // latches quando uma operacao nao usa carry ou overflow.
    always_comb begin
        result            = 32'b0;
        arithmetic_result = 33'b0;
        carry             = 1'b0;
        overflow          = 1'b0;

        case (alu_op)
            4'b0000: begin // ADD
                // As concatenacoes acrescentam zero a esquerda e transformam
                // A e B em operandos de 33 bits, preservando o carry da soma.
                // Overflow observa sinal: 0x7fff_ffff + 1 vira 0x8000_0000.
                arithmetic_result = {1'b0, a} + {1'b0, b};
                result            = arithmetic_result[31:0];
                carry             = arithmetic_result[32];
                overflow          = (~(a[31] ^ b[31])) & (result[31] ^ a[31]);
            end

            4'b0001: begin // SUB
                // A - B e calculado como A + (~B) + 1, que e o complemento de
                // dois usado pelo hardware para representar o negativo de B.
                // Em subtracoes, carry igual a 1 significa "sem emprestimo".
                // Exemplo: 10 - 3 gera result=7 e carry=1.
                arithmetic_result = {1'b0, a} + {1'b0, ~b} + 33'd1;
                result            = arithmetic_result[31:0];
                carry             = arithmetic_result[32];
                overflow          = (a[31] ^ b[31]) & (result[31] ^ a[31]);
            end

            4'b0010: result = a & b;                         // AND
            4'b0011: result = a | b;                         // OR
            4'b0100: result = a ^ b;                         // XOR

            // SLT interpreta o bit 31 como sinal; SLTU compara os mesmos bits
            // como numeros sem sinal. O resultado booleano ocupa apenas o bit 0.
            // Exemplo: 0xffff_ffff e -1 em SLT, mas e 4_294_967_295 em SLTU.
            4'b0101: result = {31'b0, $signed(a) < $signed(b)}; // SLT
            4'b0110: result = {31'b0, a < b};                // SLTU

            // Somente B[4:0] define o deslocamento, permitindo valores de 0 a 31.
            // Assim, B=36 usa 36[4:0]=4 e desloca A por quatro posicoes.
            4'b0111: result = a << b[4:0];                   // SLL
            4'b1000: result = a >> b[4:0];                   // SRL
            4'b1001: result = $signed(a) >>> b[4:0];         // SRA
            4'b1010: result = b;                             // PASS_B
            4'b1011: result = a;                             // PASS_A

            4'b1100: begin // INC
                // INC reutiliza o caminho de soma com a constante 1.
                // Em 0xffff_ffff + 1, result volta a zero e carry recebe 1.
                arithmetic_result = {1'b0, a} + 33'd1;
                result            = arithmetic_result[31:0];
                carry             = arithmetic_result[32];
                overflow          = (a == 32'h7fff_ffff);
            end

            4'b1101: begin // DEC
                // DEC equivale a A - 1 e usa o mesmo complemento de dois da SUB.
                // O caso 0x8000_0000 - 1 aciona overflow para numeros com sinal.
                arithmetic_result = {1'b0, a} + {1'b0, ~32'd1} + 33'd1;
                result            = arithmetic_result[31:0];
                carry             = arithmetic_result[32];
                overflow          = (a == 32'h8000_0000);
            end

            4'b1110: result = ~a;    // NOT
            4'b1111: result = 32'b0; // ZERO/NOP
            // O default mantem uma saida conhecida caso alu_op tenha bits X/Z
            // durante simulacao ou receba no futuro um codigo nao previsto.
            default: result = 32'b0;
        endcase

        // Estas duas flags sempre refletem o resultado final da operacao.
        // zero vale 1 quando os 32 bits sao zero; negative copia o bit de sinal.
        // Exemplo: result=0xffff_ffff gera zero=0 e negative=1.
        zero     = (result == 32'b0);
        negative = result[31];
    end

endmodule
