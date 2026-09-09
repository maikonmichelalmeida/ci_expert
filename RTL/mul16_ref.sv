// Multiplicador exato de referencia para os experimentos do projeto.
// Este modulo e independente do processador RV32I e trata a e b como unsigned.
module mul16_ref (
    input  logic        clk,
    input  logic        reset,
    input  logic [15:0] a,
    input  logic [15:0] b,
    output logic [31:0] p
);

    logic [15:0] a_reg;
    logic [15:0] b_reg;
    logic [31:0] product_comb;
    logic [31:0] product_reg;

    // Os operandos externos primeiro entram em registradores. Entre dois
    // flancos, o operador * forma o produto combinacional desses valores.
    assign product_comb = a_reg * b_reg;

    // O reset segue a convencao sincrona ativa em nivel alto do projeto.
    // No mesmo flanco, novos operandos entram e o produto anterior chega ao
    // registrador de saida. Um par capturado no flanco N aparece em p depois do
    // flanco N+1: uma latencia de um ciclo, aceitando um novo par a cada ciclo.
    always_ff @(posedge clk) begin
        if (reset) begin
            a_reg       <= 16'b0;
            b_reg       <= 16'b0;
            product_reg <= 32'b0;
        end else begin
            a_reg       <= a;
            b_reg       <= b;
            product_reg <= product_comb;
        end
    end

    assign p = product_reg;

endmodule
