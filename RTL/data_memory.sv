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

    localparam integer WORD_BYTES  = 4;
    localparam integer DEPTH       = MEM_BYTES / WORD_BYTES;
    localparam integer INDEX_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1;

    // Os quatro bancos deixam clara a habilitacao de escrita de cada byte.
    logic [7:0] mem_byte0 [0:DEPTH-1];
    logic [7:0] mem_byte1 [0:DEPTH-1];
    logic [7:0] mem_byte2 [0:DEPTH-1];
    logic [7:0] mem_byte3 [0:DEPTH-1];
    logic [INDEX_WIDTH-1:0] word_index;

    assign word_index = addr[INDEX_WIDTH+1:2];

    // Leitura e escrita acontecem somente no flanco de subida.
    always_ff @(posedge clk) begin
        if (en) begin
            rdata <= {
                mem_byte3[word_index],
                mem_byte2[word_index],
                mem_byte1[word_index],
                mem_byte0[word_index]
            };

            if (wstrb[0]) mem_byte0[word_index] <= wdata[7:0];
            if (wstrb[1]) mem_byte1[word_index] <= wdata[15:8];
            if (wstrb[2]) mem_byte2[word_index] <= wdata[23:16];
            if (wstrb[3]) mem_byte3[word_index] <= wdata[31:24];
        end
    end

`ifndef SYNTHESIS
    initial begin
        if ((MEM_BYTES < WORD_BYTES) || ((MEM_BYTES % WORD_BYTES) != 0)) begin
            $fatal(1, "MEM_BYTES must be a positive multiple of 4");
        end
    end

    always @(posedge clk) begin
        if (en && ((addr >> 2) >= DEPTH)) begin
            $error("Invalid data memory address: %h", addr);
        end
    end
`endif

endmodule
