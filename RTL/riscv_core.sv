module riscv_core (
    input  logic clk,
    input  logic reset,
    input  logic [31:0] alu_a,
    input  logic [31:0] alu_b,
    input  logic [3:0]  alu_op,
    output logic [31:0] alu_result,
    output logic        alu_zero,
    output logic        alu_negative,
    output logic        alu_carry,
    output logic        alu_overflow,
    input  logic [4:0]  rs1_addr,
    input  logic [4:0]  rs2_addr,
    input  logic [4:0]  rd_addr,
    input  logic [31:0] rd_data,
    input  logic        rd_we,
    output logic [31:0] rs1_data,
    output logic [31:0] rs2_data,
    input  logic [31:0] InstrF,
    output logic [31:0] PCF,
    output logic [31:0] PCPlus4F,
    output logic [31:0] InstrD,
    output logic [31:0] PCD,
    output logic [31:0] PCPlus4D
);

    logic StallD;
    logic FlushD;

    // A instrucao vem da IMEM externa ao core. Os sinais da hazard unit entram
    // no datapath para controlar diretamente o registrador de pipeline IF/ID.
    datapath u_datapath (
        .clk          (clk),
        .reset        (reset),
        .alu_a        (alu_a),
        .alu_b        (alu_b),
        .alu_op       (alu_op),
        .alu_result   (alu_result),
        .alu_zero     (alu_zero),
        .alu_negative (alu_negative),
        .alu_carry    (alu_carry),
        .alu_overflow (alu_overflow),
        .rs1_addr     (rs1_addr),
        .rs2_addr     (rs2_addr),
        .rd_addr      (rd_addr),
        .rd_data      (rd_data),
        .rd_we        (rd_we),
        .rs1_data     (rs1_data),
        .rs2_data     (rs2_data),
        .InstrF       (InstrF),
        .StallD       (StallD),
        .FlushD       (FlushD),
        .PCF          (PCF),
        .PCPlus4F     (PCPlus4F),
        .InstrD       (InstrD),
        .PCD          (PCD),
        .PCPlus4D     (PCPlus4D)
    );

    control_unit u_control_unit (
        .clk   (clk),
        .reset (reset)
    );

    hazard_unit u_hazard_unit (
        .clk    (clk),
        .reset  (reset),
        .StallD (StallD),
        .FlushD (FlushD)
    );

endmodule
