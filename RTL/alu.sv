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

    logic [32:0] arithmetic_result;

    always_comb begin
        result            = 32'b0;
        arithmetic_result = 33'b0;
        carry             = 1'b0;
        overflow          = 1'b0;

        case (alu_op)
            4'b0000: begin // ADD
                arithmetic_result = {1'b0, a} + {1'b0, b};
                result            = arithmetic_result[31:0];
                carry             = arithmetic_result[32];
                overflow          = (~(a[31] ^ b[31])) & (result[31] ^ a[31]);
            end

            4'b0001: begin // SUB
                // Em subtracoes, carry igual a 1 significa "sem emprestimo".
                arithmetic_result = {1'b0, a} + {1'b0, ~b} + 33'd1;
                result            = arithmetic_result[31:0];
                carry             = arithmetic_result[32];
                overflow          = (a[31] ^ b[31]) & (result[31] ^ a[31]);
            end

            4'b0010: result = a & b;                         // AND
            4'b0011: result = a | b;                         // OR
            4'b0100: result = a ^ b;                         // XOR
            4'b0101: result = {31'b0, $signed(a) < $signed(b)}; // SLT
            4'b0110: result = {31'b0, a < b};                // SLTU
            4'b0111: result = a << b[4:0];                   // SLL
            4'b1000: result = a >> b[4:0];                   // SRL
            4'b1001: result = $signed(a) >>> b[4:0];         // SRA
            4'b1010: result = b;                             // PASS_B
            4'b1011: result = a;                             // PASS_A

            4'b1100: begin // INC
                arithmetic_result = {1'b0, a} + 33'd1;
                result            = arithmetic_result[31:0];
                carry             = arithmetic_result[32];
                overflow          = (a == 32'h7fff_ffff);
            end

            4'b1101: begin // DEC
                arithmetic_result = {1'b0, a} + {1'b0, ~32'd1} + 33'd1;
                result            = arithmetic_result[31:0];
                carry             = arithmetic_result[32];
                overflow          = (a == 32'h8000_0000);
            end

            4'b1110: result = ~a;    // NOT
            4'b1111: result = 32'b0; // ZERO/NOP
            default: result = 32'b0;
        endcase

        // Estas duas flags sempre refletem o resultado final da operacao.
        zero     = (result == 32'b0);
        negative = result[31];
    end

endmodule
