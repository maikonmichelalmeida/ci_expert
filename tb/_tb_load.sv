`timescale 1ns/1ps

module tb_load;
    localparam integer PROGRAM_WORDS = 71;

    logic clk;
    logic reset;
    logic [31:0] expected_program [0:PROGRAM_WORDS-1];
    integer aligned_load_count;
    integer misaligned_load_count;
    integer load_writeback_count;
    integer suppressed_writeback_count;
    integer invalid_load_count;

    logic seen_lb_lane0;
    logic seen_lb_lane1;
    logic seen_lb_lane2;
    logic seen_lb_lane3;
    logic seen_lbu;
    logic seen_lh_low;
    logic seen_lh_high;
    logic seen_lhu;
    logic seen_lw;
    logic seen_base_m_to_e;
    logic seen_base_w_to_e;
    logic seen_base_wb_decode;
    logic seen_load_w_to_e;
    logic seen_load_wb_decode;
    logic seen_wrong_path_flush;
    logic seen_x0_destination;
    logic seen_positive_limit;
    logic seen_negative_limit;
    logic seen_negative_offset;

    riscv_system_top #(
        .IMEM_INIT_FILE ("../mem/load.hex")
    ) dut (
        .clk   (clk),
        .reset (reset)
    );

    function automatic logic [31:0] encode_addi (
        input logic signed [11:0] immediate,
        input logic [4:0] rs1,
        input logic [4:0] rd
    );
        encode_addi = {immediate, rs1, 3'b000, rd, 7'b0010011};
    endfunction

    function automatic logic [31:0] encode_lui (
        input logic [19:0] immediate,
        input logic [4:0] rd
    );
        encode_lui = {immediate, rd, 7'b0110111};
    endfunction

    function automatic logic [31:0] encode_store (
        input logic signed [11:0] immediate,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3
    );
        encode_store = {immediate[11:5], rs2, rs1, funct3,
                        immediate[4:0], 7'b0100011};
    endfunction

    function automatic logic [31:0] encode_load (
        input logic signed [11:0] immediate,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd
    );
        encode_load = {immediate, rs1, funct3, rd, 7'b0000011};
    endfunction

    function automatic logic [31:0] encode_branch (
        input logic signed [12:0] immediate,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3
    );
        encode_branch = {immediate[12], immediate[10:5], rs2, rs1, funct3,
                         immediate[4:1], immediate[11], 7'b1100011};
    endfunction

    function automatic logic [31:0] physical_word (input integer index);
        physical_word = {
            dut.u_data_memory.mem_byte3[index],
            dut.u_data_memory.mem_byte2[index],
            dut.u_data_memory.mem_byte1[index],
            dut.u_data_memory.mem_byte0[index]
        };
    endfunction

    function automatic logic load_alignment_expected (
        input logic [2:0] control,
        input logic [1:0] address_low
    );
        begin
            case (control)
                3'b000, 3'b100: load_alignment_expected = 1'b1;
                3'b001, 3'b101: load_alignment_expected = !address_low[0];
                3'b010: load_alignment_expected = (address_low == 2'b00);
                default: load_alignment_expected = 1'b0;
            endcase
        end
    endfunction

    function automatic logic [31:0] formatted_load_expected (
        input logic [31:0] raw_data,
        input logic [1:0] address_low,
        input logic [2:0] control
    );
        logic [31:0] shifted_data;
        begin
            shifted_data = raw_data >> {address_low, 3'b000};
            case (control)
                3'b000: formatted_load_expected =
                         {{24{shifted_data[7]}}, shifted_data[7:0]};
                3'b001: formatted_load_expected =
                         {{16{shifted_data[15]}}, shifted_data[15:0]};
                3'b010: formatted_load_expected = raw_data;
                3'b100: formatted_load_expected = {24'b0, shifted_data[7:0]};
                3'b101: formatted_load_expected = {16'b0, shifted_data[15:0]};
                default: formatted_load_expected = 32'b0;
            endcase
        end
    endfunction

    function automatic logic valid_load_funct3(input logic [2:0] funct3);
        valid_load_funct3 = (funct3 == 3'b000) || (funct3 == 3'b001) ||
                            (funct3 == 3'b010) || (funct3 == 3'b100) ||
                            (funct3 == 3'b101);
    endfunction

    always #5 clk = ~clk;

    // As observacoes usam apenas sinais reais do pipeline. Nenhum registrador
    // ou banco de memoria interno recebe escrita hierarquica pelo testbench.
    always @(negedge clk) begin
        logic expected_alignment;
        logic [31:0] expected_load_data;

        if (!reset) begin
            if (dut.u_riscv_core.StallF || dut.u_riscv_core.StallD)
                $fatal(1, "FAIL: LOAD checkpoint introduced a stall");

            // ---------------- Decode ----------------
            if (dut.OpD == 7'b0000011) begin
                if (valid_load_funct3(dut.Funct3D)) begin
                    if (!dut.u_riscv_core.RegWriteD ||
                        (dut.u_riscv_core.ResultSrcD !== 2'b01) ||
                        dut.u_riscv_core.MemWriteD ||
                        (dut.u_riscv_core.LoadControlD !== dut.Funct3D) ||
                        (dut.u_riscv_core.ALUControlD !== 4'b0000) ||
                        !dut.u_riscv_core.ALUSrcD || dut.u_riscv_core.ALUASrcD ||
                        (dut.u_riscv_core.ImmSrcD !== 3'b000) ||
                        dut.u_riscv_core.JumpD || dut.u_riscv_core.JalrD ||
                        dut.u_riscv_core.BranchD)
                        $fatal(1, "FAIL LOAD Decode controls at PC=%0d", dut.PCD);
                end else begin
                    if (dut.u_riscv_core.RegWriteD ||
                        (dut.u_riscv_core.ResultSrcD !== 2'b00) ||
                        dut.u_riscv_core.MemWriteD)
                        $fatal(1, "FAIL invalid LOAD has an architectural effect");
                    if ((dut.PCD == 32'd240) || (dut.PCD == 32'd244) ||
                        (dut.PCD == 32'd248))
                        invalid_load_count = invalid_load_count + 1;
                end
            end

            // ---------------- Execute ----------------
            if (dut.ResultSrcE == 2'b01) begin
                if (!dut.RegWriteE || dut.MemWriteE ||
                    !valid_load_funct3(dut.LoadControlE) ||
                    (dut.ALUControlE !== 4'b0000) || !dut.ALUSrcE ||
                    dut.ALUASrcE || (dut.ALUOperandAE !== dut.SrcAE) ||
                    (dut.SrcBE !== dut.ImmExtE) ||
                    (dut.ALUResultE !== (dut.SrcAE + dut.ImmExtE)) ||
                    dut.JumpE || dut.JalrE || dut.BranchE ||
                    dut.u_riscv_core.PCSrcE)
                    $fatal(1, "FAIL LOAD Execute path at PC=%0d", dut.PCE);
            end

            case (dut.PCE)
                32'd148: begin
                    if ((dut.ImmExtE !== 32'hffff_fffc) ||
                        (dut.SrcAE !== 32'h0000_0800) ||
                        (dut.ALUResultE !== 32'h0000_07fc))
                        $fatal(1, "FAIL negative LOAD offset");
                    seen_negative_offset = 1'b1;
                end
                32'd152: begin
                    if ((dut.SrcAE !== 32'b0) ||
                        (dut.ImmExtE !== 32'h0000_07ff) ||
                        (dut.ALUResultE !== 32'h0000_07ff))
                        $fatal(1, "FAIL I-immediate +2047 or x0 base");
                    seen_positive_limit = 1'b1;
                end
                32'd156: begin
                    if ((dut.ImmExtE !== 32'hffff_f800) ||
                        (dut.SrcAE !== 32'h0000_0800) ||
                        (dut.ALUResultE !== 32'b0))
                        $fatal(1, "FAIL I-immediate -2048");
                    seen_negative_limit = 1'b1;
                end
                32'd164: begin
                    if ((dut.u_riscv_core.ForwardAE !== 2'b10) ||
                        (dut.SrcAE !== 32'h0000_0100))
                        $fatal(1, "FAIL M-to-E forwarding for LOAD base");
                    seen_base_m_to_e = 1'b1;
                end
                32'd176: begin
                    if ((dut.u_riscv_core.ForwardAE !== 2'b01) ||
                        (dut.SrcAE !== 32'h0000_0100))
                        $fatal(1, "FAIL W-to-E forwarding for LOAD base");
                    seen_base_w_to_e = 1'b1;
                end
                32'd192: begin
                    if ((dut.u_riscv_core.ForwardAE !== 2'b00) ||
                        (dut.SrcAE !== 32'h0000_0100))
                        $fatal(1, "FAIL WB-to-Decode LOAD base reached Execute");
                end
                32'd204: begin
                    if ((dut.u_riscv_core.ForwardAE !== 2'b01) ||
                        (dut.SrcAE !== 32'h80ff_7f01))
                        $fatal(1, "FAIL W-to-E forwarding of LOAD result");
                    seen_load_w_to_e = 1'b1;
                end
                32'd220: begin
                    if ((dut.u_riscv_core.ForwardAE !== 2'b00) ||
                        (dut.SrcAE !== 32'h8001_7fff))
                        $fatal(1, "FAIL WB-to-Decode LOAD result reached Execute");
                end
                default: begin
                end
            endcase

            // ---------------- Memory ----------------
            if (dut.u_riscv_core.u_datapath.ResultSrcM == 2'b01) begin
                expected_alignment = load_alignment_expected(
                    dut.LoadControlM, dut.ALUResultM[1:0]);
                expected_load_data = formatted_load_expected(
                    dut.ReadDataM, dut.ALUResultM[1:0], dut.LoadControlM);

                if (dut.LoadAccessValidM !== expected_alignment)
                    $fatal(1, "FAIL LOAD alignment check at address %h",
                           dut.ALUResultM);
                if (dut.MemWriteM || dut.StoreEnableM ||
                    (dut.StoreWStrbM !== 4'b0000))
                    $fatal(1, "FAIL LOAD attempted to write the DMEM");

                if (expected_alignment) begin
                    if (!dut.LoadEnableM || !dut.DataMemoryEnableM ||
                        (dut.ReadDataM !== physical_word(dut.ALUResultM >> 2)) ||
                        (dut.LoadDataM !== expected_load_data))
                        $fatal(1, "FAIL LOAD MEM data at address %h",
                               dut.ALUResultM);
                    aligned_load_count = aligned_load_count + 1;
                end else begin
                    if (dut.LoadEnableM || dut.DataMemoryEnableM ||
                        (dut.LoadDataM !== 32'b0))
                        $fatal(1, "FAIL misaligned LOAD accessed the DMEM");
                    misaligned_load_count = misaligned_load_count + 1;
                end

                case (dut.LoadControlM)
                    3'b000: begin
                        case (dut.ALUResultM[1:0])
                            2'b00: seen_lb_lane0 = 1'b1;
                            2'b01: seen_lb_lane1 = 1'b1;
                            2'b10: seen_lb_lane2 = 1'b1;
                            2'b11: seen_lb_lane3 = 1'b1;
                        endcase
                    end
                    3'b001: begin
                        if (dut.ALUResultM[1]) seen_lh_high = 1'b1;
                        else seen_lh_low = 1'b1;
                    end
                    3'b010: seen_lw = 1'b1;
                    3'b100: seen_lbu = 1'b1;
                    3'b101: seen_lhu = 1'b1;
                    default: $fatal(1, "FAIL reserved LoadControlM enabled");
                endcase
            end

            // ---------------- Writeback ----------------
            if (dut.u_riscv_core.u_datapath.ResultSrcW == 2'b01) begin
                if (dut.u_riscv_core.RegWriteW) begin
                    if (dut.u_riscv_core.u_datapath.ResultW !==
                        dut.u_riscv_core.u_datapath.ReadDataW)
                        $fatal(1, "FAIL ResultSrcW=01 did not select LOAD data");
                    load_writeback_count = load_writeback_count + 1;
                    if (dut.u_riscv_core.RdW == 5'd0)
                        seen_x0_destination = 1'b1;
                end else begin
                    suppressed_writeback_count = suppressed_writeback_count + 1;
                end
            end

            if ((dut.PCD == 32'd192) && dut.u_riscv_core.RegWriteW &&
                (dut.u_riscv_core.RdW == 5'd24)) begin
                if ((dut.Rs1D !== 5'd24) || (dut.RD1D !== 32'h0000_0100))
                    $fatal(1, "FAIL WB-to-Decode bypass for LOAD base");
                seen_base_wb_decode = 1'b1;
            end

            if ((dut.PCD == 32'd220) && dut.u_riscv_core.RegWriteW &&
                (dut.u_riscv_core.RdW == 5'd28)) begin
                if ((dut.Rs1D !== 5'd28) || (dut.RD1D !== 32'h8001_7fff))
                    $fatal(1, "FAIL WB-to-Decode bypass of LOAD result");
                seen_load_wb_decode = 1'b1;
            end

            if ((dut.PCE == 32'd252) && dut.BranchE) begin
                if (!dut.u_riscv_core.PCSrcE || !dut.u_riscv_core.FlushD ||
                    !dut.u_riscv_core.FlushE || (dut.PCD !== 32'd256) ||
                    (dut.OpD !== 7'b0000011) ||
                    !dut.u_riscv_core.RegWriteD)
                    $fatal(1, "FAIL wrong-path LOAD was not selected for flush");
                seen_wrong_path_flush = 1'b1;
            end
        end
    end

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        aligned_load_count = 0;
        misaligned_load_count = 0;
        load_writeback_count = 0;
        suppressed_writeback_count = 0;
        invalid_load_count = 0;
        seen_lb_lane0 = 1'b0;
        seen_lb_lane1 = 1'b0;
        seen_lb_lane2 = 1'b0;
        seen_lb_lane3 = 1'b0;
        seen_lbu = 1'b0;
        seen_lh_low = 1'b0;
        seen_lh_high = 1'b0;
        seen_lhu = 1'b0;
        seen_lw = 1'b0;
        seen_base_m_to_e = 1'b0;
        seen_base_w_to_e = 1'b0;
        seen_base_wb_decode = 1'b0;
        seen_load_w_to_e = 1'b0;
        seen_load_wb_decode = 1'b0;
        seen_wrong_path_flush = 1'b0;
        seen_x0_destination = 1'b0;
        seen_positive_limit = 1'b0;
        seen_negative_limit = 1'b0;
        seen_negative_offset = 1'b0;

        // A lista esperada e montada pelos encoders, independentemente das
        // palavras literais do arquivo load.hex.
        expected_program[0]  = encode_addi(12'sd256, 5'd0, 5'd6);
        expected_program[1]  = encode_lui(20'h80ff8, 5'd5);
        expected_program[2]  = encode_addi(-12'sd255, 5'd5, 5'd5);
        expected_program[3]  = encode_store(12'sd0, 5'd5, 5'd6, 3'b010);
        expected_program[4]  = encode_lui(20'h80018, 5'd5);
        expected_program[5]  = encode_addi(-12'sd1, 5'd5, 5'd5);
        expected_program[6]  = encode_store(12'sd4, 5'd5, 5'd6, 3'b010);
        expected_program[7]  = encode_lui(20'hdeadc, 5'd5);
        expected_program[8]  = encode_addi(-12'sd273, 5'd5, 5'd5);
        expected_program[9]  = encode_store(12'sd8, 5'd5, 5'd6, 3'b010);
        expected_program[10] = encode_store(12'sd0, 5'd5, 5'd0, 3'b010);
        expected_program[11] = encode_lui(20'h00001, 5'd2);
        expected_program[12] = encode_addi(12'sh800, 5'd2, 5'd2);
        expected_program[13] = encode_store(-12'sd4, 5'd5, 5'd2, 3'b010);
        expected_program[14] = encode_store(12'sd12, 5'd0, 5'd6, 3'b010);
        expected_program[15] = encode_addi(-12'sd128, 5'd0, 5'd7);
        expected_program[16] = encode_store(12'sd15, 5'd7, 5'd6, 3'b000);
        expected_program[17] = encode_store(12'sd16, 5'd0, 5'd6, 3'b010);
        expected_program[18] = encode_lui(20'h00008, 5'd7);
        expected_program[19] = encode_addi(12'sd1, 5'd7, 5'd7);
        expected_program[20] = encode_store(12'sd16, 5'd7, 5'd6, 3'b001);
        expected_program[21] = encode_load(12'sd0, 5'd6, 3'b000, 5'd10);
        expected_program[22] = encode_load(12'sd1, 5'd6, 3'b000, 5'd11);
        expected_program[23] = encode_load(12'sd2, 5'd6, 3'b000, 5'd12);
        expected_program[24] = encode_load(12'sd3, 5'd6, 3'b000, 5'd13);
        expected_program[25] = encode_load(12'sd2, 5'd6, 3'b100, 5'd14);
        expected_program[26] = encode_load(12'sd3, 5'd6, 3'b100, 5'd15);
        expected_program[27] = encode_load(12'sd4, 5'd6, 3'b001, 5'd16);
        expected_program[28] = encode_load(12'sd6, 5'd6, 3'b001, 5'd17);
        expected_program[29] = encode_load(12'sd6, 5'd6, 3'b101, 5'd18);
        expected_program[30] = encode_load(12'sd8, 5'd6, 3'b010, 5'd19);
        expected_program[31] = encode_load(12'sd8, 5'd6, 3'b010, 5'd0);
        expected_program[32] = encode_load(12'sd3, 5'd6, 3'b000, 5'd0);
        expected_program[33] = encode_load(12'sd15, 5'd6, 3'b100, 5'd8);
        expected_program[34] = encode_load(12'sd15, 5'd6, 3'b000, 5'd9);
        expected_program[35] = encode_load(12'sd16, 5'd6, 3'b001, 5'd7);
        expected_program[36] = encode_load(12'sd16, 5'd6, 3'b101, 5'd20);
        expected_program[37] = encode_load(-12'sd4, 5'd2, 3'b010, 5'd21);
        expected_program[38] = encode_load(12'sd2047, 5'd0, 3'b100, 5'd22);
        expected_program[39] = encode_load(12'sh800, 5'd2, 3'b100, 5'd23);
        expected_program[40] = encode_addi(12'sd256, 5'd0, 5'd24);
        expected_program[41] = encode_load(12'sd8, 5'd24, 3'b010, 5'd25);
        expected_program[42] = encode_addi(12'sd256, 5'd0, 5'd24);
        expected_program[43] = encode_addi(12'sd0, 5'd0, 5'd31);
        expected_program[44] = encode_load(12'sd4, 5'd24, 3'b010, 5'd26);
        expected_program[45] = encode_addi(12'sd256, 5'd0, 5'd24);
        expected_program[46] = encode_addi(12'sd0, 5'd0, 5'd31);
        expected_program[47] = encode_addi(12'sd0, 5'd0, 5'd31);
        expected_program[48] = encode_load(12'sd0, 5'd24, 3'b010, 5'd27);
        expected_program[49] = encode_load(12'sd0, 5'd6, 3'b010, 5'd28);
        expected_program[50] = encode_addi(12'sd0, 5'd0, 5'd31);
        expected_program[51] = encode_addi(12'sd1, 5'd28, 5'd29);
        expected_program[52] = encode_load(12'sd4, 5'd6, 3'b010, 5'd28);
        expected_program[53] = encode_addi(12'sd0, 5'd0, 5'd31);
        expected_program[54] = encode_addi(12'sd0, 5'd0, 5'd31);
        expected_program[55] = encode_addi(12'sd1, 5'd28, 5'd30);
        expected_program[56] = encode_addi(12'sd51, 5'd0, 5'd3);
        expected_program[57] = encode_addi(12'sd68, 5'd0, 5'd4);
        expected_program[58] = encode_load(12'sd1, 5'd6, 3'b001, 5'd3);
        expected_program[59] = encode_load(12'sd2, 5'd6, 3'b010, 5'd4);
        expected_program[60] = encode_load(12'sd0, 5'd6, 3'b011, 5'd3);
        expected_program[61] = encode_load(12'sd0, 5'd6, 3'b110, 5'd4);
        expected_program[62] = encode_load(12'sd0, 5'd6, 3'b111, 5'd5);
        expected_program[63] = encode_branch(13'sd12, 5'd0, 5'd0, 3'b000);
        expected_program[64] = encode_load(12'sd8, 5'd6, 3'b010, 5'd5);
        expected_program[65] = encode_addi(12'sd1, 5'd0, 5'd5);
        expected_program[66] = encode_addi(12'sd123, 5'd0, 5'd31);
        expected_program[67] = encode_addi(12'sd0, 5'd0, 5'd0);
        expected_program[68] = encode_addi(12'sd0, 5'd0, 5'd0);
        expected_program[69] = encode_addi(12'sd0, 5'd0, 5'd0);
        expected_program[70] = encode_addi(12'sd0, 5'd0, 5'd0);

        #1;
        for (integer i = 0; i < PROGRAM_WORDS; i = i + 1) begin
            if (dut.u_instruction_memory.mem[i] !== expected_program[i])
                $fatal(1, "FAIL IMEM word %0d: hex=%h encoded=%h",
                       i, dut.u_instruction_memory.mem[i], expected_program[i]);
        end

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        repeat (90) @(posedge clk);
        @(negedge clk);

        if ((aligned_load_count != 24) || (misaligned_load_count != 2) ||
            (load_writeback_count != 24) ||
            (suppressed_writeback_count != 2) || (invalid_load_count != 3))
            $fatal(1, "FAIL LOAD counts: M=%0d badM=%0d W=%0d badW=%0d invalid=%0d",
                   aligned_load_count, misaligned_load_count,
                   load_writeback_count, suppressed_writeback_count,
                   invalid_load_count);

        if (!seen_lb_lane0 || !seen_lb_lane1 || !seen_lb_lane2 ||
            !seen_lb_lane3 || !seen_lbu || !seen_lh_low || !seen_lh_high ||
            !seen_lhu || !seen_lw || !seen_base_m_to_e ||
            !seen_base_w_to_e || !seen_base_wb_decode || !seen_load_w_to_e ||
            !seen_load_wb_decode || !seen_wrong_path_flush ||
            !seen_x0_destination || !seen_positive_limit ||
            !seen_negative_limit || !seen_negative_offset)
            $fatal(1, "FAIL: a required LOAD scenario was not observed");

        if ((physical_word(32'h100 >> 2) !== 32'h80ff_7f01) ||
            (physical_word(32'h104 >> 2) !== 32'h8001_7fff) ||
            (physical_word(32'h108 >> 2) !== 32'hdead_beef) ||
            (physical_word(32'h10c >> 2) !== 32'h8000_0000) ||
            (physical_word(32'h110 >> 2) !== 32'h0000_8001) ||
            (physical_word(32'h000 >> 2) !== 32'hdead_beef) ||
            (physical_word(32'h7fc >> 2) !== 32'hdead_beef))
            $fatal(1, "FAIL STORE/LOAD integration changed physical memory");

        if ((dut.u_riscv_core.u_datapath.u_register_file.regs[0] !== 32'b0) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[3] !== 32'd51) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[4] !== 32'd68) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[5] !== 32'hdead_beef) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[7] !== 32'h0000_8001) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[8] !== 32'h0000_0080) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[9] !== 32'hffff_ff80) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[10] !== 32'h0000_0001) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[11] !== 32'h0000_007f) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[12] !== 32'hffff_ffff) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[13] !== 32'hffff_ff80) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[14] !== 32'h0000_00ff) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[15] !== 32'h0000_0080) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[16] !== 32'h0000_7fff) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[17] !== 32'hffff_8001) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[18] !== 32'h0000_8001) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[19] !== 32'hdead_beef) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[20] !== 32'h0000_8001) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[21] !== 32'hdead_beef) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[22] !== 32'h0000_00de) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[23] !== 32'h0000_00ef) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[25] !== 32'hdead_beef) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[26] !== 32'h8001_7fff) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[27] !== 32'h80ff_7f01) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[28] !== 32'h8001_7fff) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[29] !== 32'h80ff_7f02) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[30] !== 32'h8001_8000) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[31] !== 32'd123))
            $fatal(1, "FAIL final Register File LOAD results");

        $display("PASS: LB/LBU lanes and LH/LHU sign/zero extension");
        $display("PASS: LW, offsets, immediate limits and x0 behavior");
        $display("PASS: LOAD base forwarding and LOAD result W-to-E/WB-to-Decode");
        $display("PASS: invalid, misaligned and wrong-path LOADs are suppressed");
        $display("PASS: LOAD/STORE integration preserves the classic DMEM timing");
        $display("PASS: LOAD checkpoint complete; load-use stall remains pending");
        $finish;
    end

endmodule
