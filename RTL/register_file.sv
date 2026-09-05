// Banco de 32 registradores de 32 bits do RV32I, de x0 ate x31.
// Possui duas leituras simultaneas e uma escrita sincronizada pelo clock.
module register_file (
    input  logic        clk,
    input  logic [4:0]  rs1_addr,
    input  logic [4:0]  rs2_addr,
    input  logic [4:0]  rd_addr,
    input  logic [31:0] rd_data,
    input  logic        rd_we,
    output logic [31:0] rs1_data,
    output logic [31:0] rs2_data
);

    // Um endereco de 5 bits possui 32 combinacoes e seleciona uma das 32 linhas.
    // E como se regs[5] fosse o registrador arquitetural x5.
    logic [31:0] regs [0:31];

    // A escrita acontece somente no flanco de subida do clock e quando rd_we=1.
    // rd_addr=0 e bloqueado para cumprir a regra arquitetural de que x0 e imutavel.
    // Exemplo: rd_we=1, rd_addr=5 e rd_data=10 grava o valor 10 em x5.
    always_ff @(posedge clk) begin
        if (rd_we && (rd_addr != 5'd0)) begin
            regs[rd_addr] <= rd_data;
        end
    end

    // As leituras sao combinacionais: mudar rs1_addr ou rs2_addr muda a saida
    // sem esperar o clock. Cada ternario funciona como um mux que devolve zero
    // para o endereco 0 ou o conteudo de regs para os enderecos de 1 a 31.
    assign rs1_data = (rs1_addr == 5'd0) ? 32'b0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? 32'b0 : regs[rs2_addr];

endmodule
