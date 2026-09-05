// Memoria de instrucoes conectada ao estagio Fetch.
// PCF fornece o endereco em bytes e rdata forma o sinal InstrF do diagrama.
module instruction_memory #(
    parameter integer MEM_BYTES = 2048,
    parameter         INIT_FILE = ""
)(
    input  logic        clk,
    input  logic        en,
    input  logic [31:0] addr,
    output logic [31:0] rdata
);

    // MEM_BYTES informa o tamanho total em bytes. Como cada instrucao deste
    // baseline RV32I ocupa 4 bytes, 2048/4 resulta em DEPTH=512 palavras.
    localparam integer WORD_BYTES  = 4;
    localparam integer DEPTH       = MEM_BYTES / WORD_BYTES;

    // $clog2 calcula a quantidade de bits do indice. Para DEPTH=512,
    // $clog2(512)=9: nove bits selecionam mem[0] ate mem[511].
    // O ternario evita declarar um vetor de largura zero se DEPTH for 1.
    localparam integer INDEX_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1;

    // Cada posicao guarda uma instrucao completa de 32 bits.
    logic [31:0] mem [0:DEPTH-1];
    logic [INDEX_WIDTH-1:0] word_index;

    // Os dois bits baixos sao descartados porque PCF avanca de quatro em quatro.
    // Com INDEX_WIDTH=9, a expressao equivale a addr[10:2]. Assim, os enderecos
    // 0x000, 0x004 e 0x008 selecionam respectivamente os indices 0, 1 e 2.
    assign word_index = addr[INDEX_WIDTH+1:2];

    // INIT_FILE permite carregar um programa hexadecimal no inicio da simulacao.
    // Cada linha do arquivo preenche uma palavra consecutiva da memoria.
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    // Cada instrucao RV32I ocupa quatro bytes. Por isso, os dois bits menos
    // significativos nao participam do indice usado para acessar a memoria.
    // A leitura e combinacional para que InstrF acompanhe diretamente o PCF.
    // O ternario funciona como enable: en=1 entrega mem[word_index]; en=0 entrega 0.
    assign rdata = en ? mem[word_index] : 32'b0;

`ifndef SYNTHESIS
    // Os blocos abaixo sao verificacoes de simulacao e nao fazem parte do circuito.
    initial begin
        if ((MEM_BYTES < WORD_BYTES) || ((MEM_BYTES % WORD_BYTES) != 0)) begin
            $fatal(1, "MEM_BYTES must be a positive multiple of 4");
        end
    end

    always @(posedge clk) begin
        // Sem instrucoes comprimidas, um endereco de instrucao deve ser multiplo
        // de 4. O deslocamento addr>>2 tambem detecta indices alem de DEPTH-1.
        if (en && ((addr[1:0] != 2'b00) || ((addr >> 2) >= DEPTH))) begin
            $error("Invalid instruction memory address: %h", addr);
        end
    end
`endif

endmodule
