module instruction_memory #(
    parameter integer MEM_BYTES = 2048,
    parameter         INIT_FILE = ""
)(
    input  logic        clk,
    input  logic        en,
    input  logic [31:0] addr,
    output logic [31:0] rdata
);

    localparam integer WORD_BYTES  = 4;
    localparam integer DEPTH       = MEM_BYTES / WORD_BYTES;
    localparam integer INDEX_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1;

    logic [31:0] mem [0:DEPTH-1];
    logic [INDEX_WIDTH-1:0] word_index;

    assign word_index = addr[INDEX_WIDTH+1:2];

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    // Cada instrucao RV32I ocupa quatro bytes. Por isso, os dois bits menos
    // significativos nao participam do indice usado para acessar a memoria.
    // A leitura e combinacional para que InstrF acompanhe diretamente o PCF.
    assign rdata = en ? mem[word_index] : 32'b0;

`ifndef SYNTHESIS
    initial begin
        if ((MEM_BYTES < WORD_BYTES) || ((MEM_BYTES % WORD_BYTES) != 0)) begin
            $fatal(1, "MEM_BYTES must be a positive multiple of 4");
        end
    end

    always @(posedge clk) begin
        if (en && ((addr[1:0] != 2'b00) || ((addr >> 2) >= DEPTH))) begin
            $error("Invalid instruction memory address: %h", addr);
        end
    end
`endif

endmodule
