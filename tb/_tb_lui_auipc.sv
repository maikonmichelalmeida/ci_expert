`timescale 1ns/1ps

module tb_lui_auipc;
    localparam integer PROGRAM_WORDS = 30;
    localparam logic [3:0] ALU_ADD    = 4'b0000;
    localparam logic [3:0] ALU_PASS_B = 4'b1010;

    logic clk;
    logic reset;
    logic [31:0] expected_program [0:PROGRAM_WORDS-1];
    logic [31:0] execute_instruction;
    logic [6:0]  execute_opcode;
    logic [31:0] expected_immediate;
    logic [31:0] expected_result;
    integer u_execute_count;
    logic seen_lui_forward_m;
    logic seen_auipc_forward_m;
    logic seen_forward_w;
    logic seen_wb_decode;
    logic seen_wb_decode_execute;
    logic seen_spurious_lui_forward;
    logic seen_spurious_auipc_forward;
    logic seen_x0_read;

    riscv_system_top #(
        .IMEM_INIT_FILE ("../mem/lui_auipc.hex")
    ) dut (
        .clk   (clk),
        .reset (reset)
    );

    function automatic logic [31:0] encode_lui (
        input logic [19:0] imm20,
        input logic [4:0]  rd
    );
        encode_lui = {imm20, rd, 7'b0110111};
    endfunction

    function automatic logic [31:0] encode_auipc (
        input logic [19:0] imm20,
        input logic [4:0]  rd
    );
        encode_auipc = {imm20, rd, 7'b0010111};
    endfunction

    function automatic logic [31:0] encode_addi (
        input logic signed [11:0] immediate,
        input logic [4:0] rs1,
        input logic [4:0] rd
    );
        encode_addi = {immediate, rs1, 3'b000, rd, 7'b0010011};
    endfunction

    always #5 clk = ~clk;

    // As verificacoes ocorrem no negedge, quando todos os registradores
    // atualizados no posedge anterior ja estao estaveis.
    always @(negedge clk) begin
        if (!reset) begin
            if (dut.MemWriteM !== 1'b0)
                $fatal(1, "FAIL: LUI/AUIPC program asserted MemWriteM");
            if ((dut.u_data_memory.en !== 1'b0) ||
                (dut.u_data_memory.wstrb !== 4'b0000))
                $fatal(1, "FAIL: dedicated test activated the DMEM");

            if (dut.u_riscv_core.RegWriteE &&
                (dut.PCE < (PROGRAM_WORDS * 4))) begin
                execute_instruction = expected_program[dut.PCE >> 2];
                execute_opcode = execute_instruction[6:0];

                if ((execute_opcode == 7'b0110111) ||
                    (execute_opcode == 7'b0010111)) begin
                    expected_immediate = {execute_instruction[31:12], 12'b0};
                    expected_result = (execute_opcode == 7'b0010111)
                                    ? dut.PCE + expected_immediate
                                    : expected_immediate;

                    if ((dut.ResultSrcE !== 2'b00) ||
                        (dut.MemWriteE !== 1'b0) ||
                        (dut.JumpE !== 1'b0) || (dut.JalrE !== 1'b0) ||
                        (dut.BranchE !== 1'b0) ||
                        (dut.ALUSrcE !== 1'b1) ||
                        (dut.SrcBE !== expected_immediate) ||
                        (dut.ALUResultE !== expected_result) ||
                        (dut.u_riscv_core.PCSrcE !== 1'b0) ||
                        (dut.u_riscv_core.FlushD !== 1'b0) ||
                        (dut.u_riscv_core.FlushE !== 1'b0))
                        $fatal(1, "FAIL U-type Execute controls at PC=%0d", dut.PCE);

                    if (execute_opcode == 7'b0110111) begin
                        if ((dut.ALUASrcE !== 1'b0) ||
                            (dut.ALUControlE !== ALU_PASS_B))
                            $fatal(1, "FAIL LUI Execute path at PC=%0d", dut.PCE);
                    end else begin
                        if ((dut.ALUASrcE !== 1'b1) ||
                            (dut.ALUControlE !== ALU_ADD) ||
                            (dut.ALUOperandAE !== dut.PCE))
                            $fatal(1, "FAIL AUIPC Execute path at PC=%0d", dut.PCE);
                    end
                    u_execute_count = u_execute_count + 1;
                end
            end

            case (dut.PCE)
                32'd32: begin
                    if ((dut.u_riscv_core.ForwardAE !== 2'b10) ||
                        (dut.SrcAE !== 32'h0000_1000))
                        $fatal(1, "FAIL immediate LUI consumer forwarding");
                    seen_lui_forward_m = 1'b1;
                end
                32'd40: begin
                    if ((dut.u_riscv_core.ForwardAE !== 2'b10) ||
                        (dut.SrcAE !== 32'h0000_1024))
                        $fatal(1, "FAIL immediate AUIPC consumer forwarding");
                    seen_auipc_forward_m = 1'b1;
                end
                32'd52: begin
                    if ((dut.u_riscv_core.ForwardAE !== 2'b01) ||
                        (dut.SrcAE !== 32'h0000_2000))
                        $fatal(1, "FAIL W -> E forwarding for U-type result");
                    seen_forward_w = 1'b1;
                end
                32'd68: begin
                    if ((dut.u_riscv_core.ForwardAE !== 2'b00) ||
                        (dut.SrcAE !== 32'h0000_3000))
                        $fatal(1, "FAIL operand captured by WB -> Decode bypass");
                    seen_wb_decode_execute = 1'b1;
                end
                32'd92: begin
                    if ((dut.u_riscv_core.ForwardAE !== 2'b10) ||
                        (dut.ALUResultE !== 32'h0001_8000))
                        $fatal(1, "FAIL LUI with irrelevant extracted rs1 forwarding");
                    seen_spurious_lui_forward = 1'b1;
                end
                32'd100: begin
                    if ((dut.u_riscv_core.ForwardAE !== 2'b10) ||
                        (dut.SrcAE !== 32'd55) ||
                        (dut.ALUOperandAE !== 32'd100) ||
                        (dut.ALUResultE !== 32'h0002_0064))
                        $fatal(1, "FAIL AUIPC did not ignore extracted rs1 forwarding");
                    seen_spurious_auipc_forward = 1'b1;
                end
                default: begin
                end
            endcase

            if ((dut.PCD == 32'd68) && dut.u_riscv_core.RegWriteW &&
                (dut.u_riscv_core.RdW == 5'd22)) begin
                if ((dut.Rs1D !== 5'd22) ||
                    (dut.RD1D !== dut.u_riscv_core.u_datapath.ResultW) ||
                    (dut.RD1D !== 32'h0000_3000))
                    $fatal(1, "FAIL WB -> Decode bypass for LUI producer");
                seen_wb_decode = 1'b1;
            end

            if (dut.PCD == 32'd104) begin
                if ((dut.Rs1D !== 5'd0) || (dut.Rs2D !== 5'd0) ||
                    (dut.RD1D !== 32'b0) || (dut.RD2D !== 32'b0))
                    $fatal(1, "FAIL: x0 did not remain architecturally zero");
                seen_x0_read = 1'b1;
            end
        end
    end

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        u_execute_count = 0;
        seen_lui_forward_m = 1'b0;
        seen_auipc_forward_m = 1'b0;
        seen_forward_w = 1'b0;
        seen_wb_decode = 1'b0;
        seen_wb_decode_execute = 1'b0;
        seen_spurious_lui_forward = 1'b0;
        seen_spurious_auipc_forward = 1'b0;
        seen_x0_read = 1'b0;

        // A imagem esperada e montada por encoders independentes do arquivo hex.
        expected_program[0]  = encode_lui(20'h12345, 5'd5);
        expected_program[1]  = encode_lui(20'hfffff, 5'd6);
        expected_program[2]  = encode_lui(20'h80000, 5'd7);
        expected_program[3]  = encode_lui(20'habcdE, 5'd0);
        expected_program[4]  = encode_auipc(20'h00000, 5'd10);
        expected_program[5]  = encode_auipc(20'h00001, 5'd11);
        expected_program[6]  = encode_auipc(20'hfffff, 5'd12);
        expected_program[7]  = encode_lui(20'h00001, 5'd15);
        expected_program[8]  = encode_addi(12'sd5, 5'd15, 5'd16);
        expected_program[9]  = encode_auipc(20'h00001, 5'd17);
        expected_program[10] = encode_addi(12'sd4, 5'd17, 5'd18);
        expected_program[11] = encode_lui(20'h00002, 5'd19);
        expected_program[12] = encode_addi(12'sd7, 5'd0, 5'd20);
        expected_program[13] = encode_addi(12'sd9, 5'd19, 5'd21);
        expected_program[14] = encode_lui(20'h00003, 5'd22);
        expected_program[15] = encode_addi(12'sd1, 5'd0, 5'd23);
        expected_program[16] = encode_addi(12'sd2, 5'd0, 5'd24);
        expected_program[17] = encode_addi(12'sd4, 5'd22, 5'd25);
        expected_program[18] = encode_lui(20'h00001, 5'd2);
        expected_program[19] = encode_addi(12'sh800, 5'd2, 5'd2);
        expected_program[20] = encode_auipc(20'h00000, 5'd14);
        expected_program[21] = encode_addi(12'sd16, 5'd14, 5'd14);
        expected_program[22] = encode_addi(12'sd77, 5'd0, 5'd3);
        expected_program[23] = encode_lui(20'h00018, 5'd26);
        expected_program[24] = encode_addi(12'sd55, 5'd0, 5'd4);
        expected_program[25] = encode_auipc(20'h00020, 5'd27);
        expected_program[26] = encode_addi(12'sd0, 5'd0, 5'd0);
        expected_program[27] = encode_addi(12'sd0, 5'd0, 5'd0);
        expected_program[28] = encode_addi(12'sd0, 5'd0, 5'd0);
        expected_program[29] = encode_addi(12'sd0, 5'd0, 5'd0);

        #1;
        for (integer i = 0; i < PROGRAM_WORDS; i = i + 1) begin
            if (dut.u_instruction_memory.mem[i] !== expected_program[i])
                $fatal(1, "FAIL IMEM word %0d: hex=%h encoded=%h",
                       i, dut.u_instruction_memory.mem[i], expected_program[i]);
        end
        $display("PASS: IMEM matches independent LUI/AUIPC encoders");

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        repeat (40) @(posedge clk);
        @(negedge clk);

        if (u_execute_count != 15)
            $fatal(1, "FAIL: observed %0d U-type instructions, expected 15",
                   u_execute_count);
        if (!seen_lui_forward_m || !seen_auipc_forward_m || !seen_forward_w ||
            !seen_wb_decode || !seen_wb_decode_execute ||
            !seen_spurious_lui_forward || !seen_spurious_auipc_forward ||
            !seen_x0_read)
            $fatal(1, "FAIL: one forwarding or WB -> Decode scenario was not seen");

        if ((dut.u_riscv_core.u_datapath.u_register_file.regs[5] !== 32'h1234_5000) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[6] !== 32'hffff_f000) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[7] !== 32'h8000_0000) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[10] !== 32'h0000_0010) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[11] !== 32'h0000_1014) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[12] !== 32'hffff_f018))
            $fatal(1, "FAIL: basic LUI/AUIPC architectural results");

        if ((dut.u_riscv_core.u_datapath.u_register_file.regs[16] !== 32'h0000_1005) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[18] !== 32'h0000_1028) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[21] !== 32'h0000_2009) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[25] !== 32'h0000_3004))
            $fatal(1, "FAIL: U-type consumers received an incorrect value");

        if (dut.u_riscv_core.u_datapath.u_register_file.regs[2] !== 32'h0000_0800)
            $fatal(1, "FAIL: software did not form x2=0x00000800");
        if (dut.u_riscv_core.u_datapath.u_register_file.regs[14] !== 32'h0000_0060)
            $fatal(1, "FAIL: AUIPC+ADDI PC-relative value is incorrect");
        if ((dut.u_riscv_core.u_datapath.u_register_file.regs[26] !== 32'h0001_8000) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[27] !== 32'h0002_0064))
            $fatal(1, "FAIL: U-type result was changed by irrelevant forwarding");

        $display("PASS: LUI constants, x0 protection and ALU writeback");
        $display("PASS: AUIPC uses PCE and keeps ResultSrc=00");
        $display("PASS: M/W forwarding and WB -> Decode bypass");
        $display("PASS: x2=0x00000800 and PC-relative AUIPC+ADDI");
        $display("PASS: LUI/AUIPC checkpoint completed without LOAD/STORE");
        $finish;
    end

endmodule
