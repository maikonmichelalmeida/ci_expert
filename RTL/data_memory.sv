// Memoria de dados configuravel, com 2 KiB por padrao, em quatro bancos de bytes.
// A separacao por bytes permite escritas de SB, SH e SW por meio de wstrb.
module data_memory #(
    parameter integer MEM_BYTES = 2048
)(
    input  logic        clk,
    input  logic        en,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    input  logic [3:0]  wstrb,
    output logic [31:0] rdata
);

    // Uma palavra RV32I possui 4 bytes. Com MEM_BYTES=2048, a divisao
    // 2048/4 cria DEPTH=512 posicoes de 32 bits.
    localparam integer WORD_BYTES  = 4;
    localparam integer DEPTH       = MEM_BYTES / WORD_BYTES;

    // Calcula quantos bits sao necessarios para selecionar todas as palavras.
    // Exemplo: $clog2(512)=9, entao o indice vai de mem[0] ate mem[511].
    // O ternario impede largura zero no caso especial de DEPTH igual a 1.
    localparam integer INDEX_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1;

    // Os quatro bancos deixam clara a habilitacao de escrita de cada byte.
    // byte0 representa wdata[7:0] e byte3 representa wdata[31:24].
    logic [7:0] mem_byte0 [0:DEPTH-1];
    logic [7:0] mem_byte1 [0:DEPTH-1];
    logic [7:0] mem_byte2 [0:DEPTH-1];
    logic [7:0] mem_byte3 [0:DEPTH-1];
    logic [INDEX_WIDTH-1:0] word_index;

    // Os bits [1:0] indicam o byte dentro da palavra e nao entram no indice.
    // Para 512 palavras, INDEX_WIDTH=9 e esta selecao equivale a addr[10:2].
    // Exemplo: addr=0x000 seleciona indice 0; addr=0x004 seleciona indice 1.
    assign word_index = addr[INDEX_WIDTH+1:2];

    // No pipeline classico, ReadDataM precisa aparecer durante o proprio ciclo
    // MEM para o MEM/WB captura-lo no proximo posedge. Por isso a leitura nao
    // possui registrador interno: mudar addr muda rdata combinacionalmente.
    always_comb begin
        rdata = 32'b0;

        if (en) begin
            // A concatenacao recompõe a palavra little-endian: o byte do banco
            // mais alto ocupa rdata[31:24] e byte0 ocupa rdata[7:0].
            rdata = {
                mem_byte3[word_index],
                mem_byte2[word_index],
                mem_byte1[word_index],
                mem_byte0[word_index]
            };
        end
    end

    // A escrita continua exclusivamente no flanco de subida. E como se en
    // fosse a chave geral e cada bit de wstrb liberasse apenas um byte bank.
    always_ff @(posedge clk) begin
        if (en) begin
            // Cada bit de wstrb habilita somente seu banco. Por exemplo,
            // wstrb=4'b0010 altera apenas os bits [15:8] da palavra armazenada.
            if (wstrb[0]) mem_byte0[word_index] <= wdata[7:0];
            if (wstrb[1]) mem_byte1[word_index] <= wdata[15:8];
            if (wstrb[2]) mem_byte2[word_index] <= wdata[23:16];
            if (wstrb[3]) mem_byte3[word_index] <= wdata[31:24];
        end
    end

`ifndef SYNTHESIS
    // Estas verificacoes existem apenas na simulacao e nao geram hardware.
    // O tamanho precisa formar um numero inteiro e positivo de palavras.
    initial begin
        if ((MEM_BYTES < WORD_BYTES) || ((MEM_BYTES % WORD_BYTES) != 0)) begin
            $fatal(1, "MEM_BYTES must be a positive multiple of 4");
        end
    end

    always @(posedge clk) begin
        // addr>>2 converte endereco em bytes para indice de palavra.
        // Nao se testa addr[1:0]: a futura LSU decidira o alinhamento conforme
        // o acesso seja byte, halfword ou word.
        if (en && ((addr >> 2) >= DEPTH)) begin
            $error("Invalid data memory address: %h", addr);
        end
    end
`endif

endmodule
