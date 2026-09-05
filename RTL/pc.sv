// Program Counter do estagio Fetch.
// PCF e o endereco da instrucao atual; PCNextF e o valor que podera substitui-lo.
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
    // Exemplo: PCF=0x0000_0008 gera PCPlus4F=0x0000_000c.
    assign PCPlus4F = PCF + 32'd4;

    // Este ternario representa o mux desenhado antes da entrada do PC:
    // PCSrcE=0 escolhe PC+4; PCSrcE=1 escolhe o futuro alvo de branch/jump.
    assign PCNextF  = PCSrcE ? PCTargetE : PCPlus4F;

    // Reset e StallF sao sincronos: com StallF ativo, PCF conserva seu valor.
    // Sem reset nem stall, cada flanco copia PCNextF para o registrador PCF.
    always_ff @(posedge clk) begin
        if (reset) begin
            PCF <= 32'h0000_0000;
        end else if (!StallF) begin
            PCF <= PCNextF;
        end
    end

endmodule
