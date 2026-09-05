module pc (
    input  logic        clk,
    input  logic        reset,
    input  logic        PCSrcE,
    input  logic [31:0] PCTargetE,
    input  logic        StallF,
    output logic [31:0] PCF,
    output logic [31:0] PCPlus4F,
    output logic [31:0] PCNextF
);

    // O caminho normal busca a proxima palavra. Quando branches e jumps forem
    // implementados, PCSrcE selecionara o endereco alternativo PCTargetE.
    assign PCPlus4F = PCF + 32'd4;
    assign PCNextF  = PCSrcE ? PCTargetE : PCPlus4F;

    // Reset e StallF sao sincronos: com StallF ativo, PCF conserva seu valor.
    always_ff @(posedge clk) begin
        if (reset) begin
            PCF <= 32'h0000_0000;
        end else if (!StallF) begin
            PCF <= PCNextF;
        end
    end

endmodule
