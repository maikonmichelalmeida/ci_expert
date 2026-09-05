// Futuro bloco de decodificacao e controle do processador.
// E como se fosse o bloco que le opcode/funct e distribui comandos para ALU,
// banco de registradores, memorias e registradores de pipeline.
module control_unit (
    input  logic       clk,
    input  logic       reset,
    input  logic [6:0] OpD,
    input  logic [2:0] Funct3D,
    input  logic       Funct7b5D,
    output logic       RegWriteD,
    output logic [1:0] ResultSrcD,
    output logic       MemWriteD,
    output logic       JumpD,
    output logic       BranchD,
    output logic [3:0] ALUControlD,
    output logic       ALUSrcD,
    output logic [2:0] ImmSrcD
);

    // A interface definitiva ja recebe os campos de InstrD, mas eles ainda nao
    // sao interpretados. Os zeros mantem escrita, salto, branch e memoria
    // desativados; tambem escolhem as entradas de mux mais simples do diagrama.
    assign RegWriteD   = 1'b0;
    assign ResultSrcD  = 2'b00;
    assign MemWriteD   = 1'b0;
    assign JumpD       = 1'b0;
    assign BranchD     = 1'b0;
    assign ALUControlD = 4'b0000;
    assign ALUSrcD     = 1'b0;
    assign ImmSrcD     = 3'b000;

    // clk e reset permanecem na interface estrutural do modulo. Nenhum estado
    // interno e criado nesta etapa, pois o decoder funcional vira depois.

endmodule
