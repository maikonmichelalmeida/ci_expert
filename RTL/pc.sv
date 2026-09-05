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

    assign PCPlus4F = PCF + 32'd4;
    assign PCNextF  = PCSrcE ? PCTargetE : PCPlus4F;

    always_ff @(posedge clk) begin
        if (reset) begin
            PCF <= 32'h0000_0000;
        end else if (!StallF) begin
            PCF <= PCNextF;
        end
    end

endmodule
