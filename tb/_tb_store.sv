`timescale 1ns/1ps

module tb_store;
    localparam integer PROGRAM_WORDS = 53;
    localparam integer DMEM_WORDS    = 512;

    logic clk;
    logic reset;
    logic [31:0] expected_program [0:PROGRAM_WORDS-1];
    logic [31:0] expected_memory [0:DMEM_WORDS-1];
    logic        expected_memory_valid [0:DMEM_WORDS-1];

    logic sampled_enable;
    logic sampled_mem_write;
    logic [2:0] sampled_control;
    logic [31:0] sampled_address;
    logic [31:0] sampled_write_data;
    logic [31:0] sampled_store_data;
    logic [3:0] sampled_wstrb;
    logic [3:0] expected_wstrb;
    logic [31:0] expected_store_data;
    integer sampled_index;
    integer store_count;
    integer suppressed_count;

    logic seen_double_forward;
    logic seen_m_priority;
    logic seen_wb_decode;
    logic seen_wb_decode_execute;
    logic seen_positive_offset;
    logic seen_negative_offset;
    logic seen_x0_base;
    logic seen_wrong_path_flush;
    logic seen_invalid_011;
    logic seen_invalid_111;

    riscv_system_top #(
        .IMEM_INIT_FILE ("../mem/store.hex")
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

    function automatic logic [31:0] encode_branch (
        input logic signed [12:0] immediate,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3
    );
        encode_branch = {immediate[12], immediate[10:5], rs2, rs1, funct3,
                         immediate[4:1], immediate[11], 7'b1100011};
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

    function automatic logic [31:0] physical_word (input integer index);
        physical_word = {
            dut.u_data_memory.mem_byte3[index],
            dut.u_data_memory.mem_byte2[index],
            dut.u_data_memory.mem_byte1[index],
            dut.u_data_memory.mem_byte0[index]
        };
    endfunction

    always #5 clk = ~clk;

    // Captura os sinais do ciclo MEM antes do posedge atualizar o EX/MEM.
    // Depois de #1, a escrita sincrona da DMEM ja atualizou os byte banks.
    always @(posedge clk) begin
        sampled_enable    = dut.StoreEnableM;
        sampled_mem_write = dut.MemWriteM;
        sampled_control   = dut.StoreControlM;
        sampled_address   = dut.ALUResultM;
        sampled_write_data = dut.WriteDataM;
        sampled_store_data = dut.StoreDataM;
        sampled_wstrb      = dut.StoreWStrbM;
        sampled_index      = dut.ALUResultM >> 2;

        if (!reset) begin
            expected_wstrb = 4'b0000;
            expected_store_data = 32'b0;

            if (sampled_enable) begin
                case (sampled_control)
                    3'b000: begin
                        expected_wstrb = 4'b0001 << sampled_address[1:0];
                        expected_store_data = sampled_write_data <<
                                              {sampled_address[1:0], 3'b000};
                    end
                    3'b001: begin
                        expected_wstrb = 4'b0011 << sampled_address[1:0];
                        expected_store_data = sampled_write_data <<
                                              {sampled_address[1:0], 3'b000};
                    end
                    3'b010: begin
                        expected_wstrb = 4'b1111;
                        expected_store_data = sampled_write_data;
                    end
                    default: $fatal(1, "FAIL: enabled reserved STORE type");
                endcase

                if (!sampled_mem_write || (sampled_wstrb !== expected_wstrb) ||
                    (sampled_store_data !== expected_store_data))
                    $fatal(1, "FAIL STORE adapter at address %h", sampled_address);

                #1;
                if (!expected_memory_valid[sampled_index] &&
                    (sampled_wstrb != 4'b1111))
                    $fatal(1, "FAIL: partial store reached an uninitialized model word");

                if (sampled_wstrb[0]) expected_memory[sampled_index][7:0]
                    = sampled_store_data[7:0];
                if (sampled_wstrb[1]) expected_memory[sampled_index][15:8]
                    = sampled_store_data[15:8];
                if (sampled_wstrb[2]) expected_memory[sampled_index][23:16]
                    = sampled_store_data[23:16];
                if (sampled_wstrb[3]) expected_memory[sampled_index][31:24]
                    = sampled_store_data[31:24];
                if (sampled_wstrb == 4'b1111)
                    expected_memory_valid[sampled_index] = 1'b1;

                if (expected_memory_valid[sampled_index] &&
                    (physical_word(sampled_index) !== expected_memory[sampled_index]))
                    $fatal(1, "FAIL byte preservation at address %h", sampled_address);
                store_count = store_count + 1;
            end else if (sampled_mem_write) begin
                if (sampled_wstrb !== 4'b0000)
                    $fatal(1, "FAIL: suppressed store produced a write strobe");
                #1;
                if (expected_memory_valid[sampled_index] &&
                    (physical_word(sampled_index) !== expected_memory[sampled_index]))
                    $fatal(1, "FAIL: misaligned store changed memory");
                suppressed_count = suppressed_count + 1;
            end else if (sampled_wstrb !== 4'b0000) begin
                $fatal(1, "FAIL: wstrb active without MemWriteM");
            end
        end
    end

    // Observa o caminho arquitetural no Execute sem dirigir nenhum estado RTL.
    always @(negedge clk) begin
        if (!reset) begin
            if (dut.MemWriteE) begin
                if ((dut.RegWriteE !== 1'b0) || (dut.ResultSrcE !== 2'b00) ||
                    (dut.StoreControlE > 3'b010) ||
                    (dut.ALUSrcE !== 1'b1) || (dut.ALUASrcE !== 1'b0) ||
                    (dut.ALUControlE !== 4'b0000) ||
                    (dut.ALUOperandAE !== dut.SrcAE) ||
                    (dut.SrcBE !== dut.ImmExtE) ||
                    (dut.ALUResultE !== (dut.SrcAE + dut.ImmExtE)) ||
                    (dut.JumpE !== 1'b0) || (dut.JalrE !== 1'b0) ||
                    (dut.BranchE !== 1'b0) ||
                    (dut.u_riscv_core.PCSrcE !== 1'b0) ||
                    (dut.u_riscv_core.FlushD !== 1'b0) ||
                    (dut.u_riscv_core.FlushE !== 1'b0) ||
                    (dut.u_riscv_core.StallF !== 1'b0) ||
                    (dut.u_riscv_core.StallD !== 1'b0))
                    $fatal(1, "FAIL STORE Execute controls at PC=%0d", dut.PCE);
            end

            if (dut.MemWriteM && (dut.u_riscv_core.RegWriteM !== 1'b0))
                $fatal(1, "FAIL: STORE attempted Register File write");

            case (dut.PCE)
                32'd80: begin
                    if ((dut.ALUResultE !== 32'h0000_010c) ||
                        (dut.ImmExtE !== 32'd12))
                        $fatal(1, "FAIL positive STORE offset");
                    seen_positive_offset = 1'b1;
                end
                32'd88: begin
                    if ((dut.u_riscv_core.ForwardAE !== 2'b00) ||
                        (dut.SrcAE !== 32'b0) || (dut.ALUResultE !== 32'b0))
                        $fatal(1, "FAIL x0 as STORE base");
                    seen_x0_base = 1'b1;
                end
                32'd100: begin
                    if ((dut.u_riscv_core.ForwardAE !== 2'b10) ||
                        (dut.SrcAE !== 32'h0000_0800) ||
                        (dut.ImmExtE !== 32'hffff_fffc) ||
                        (dut.ALUResultE !== 32'h0000_07fc))
                        $fatal(1, "FAIL negative STORE offset/boundary address");
                    seen_negative_offset = 1'b1;
                end
                32'd112: begin
                    if ((dut.u_riscv_core.ForwardAE !== 2'b10) ||
                        (dut.u_riscv_core.ForwardBE !== 2'b01) ||
                        (dut.SrcAE !== 32'h0000_0120) ||
                        (dut.WriteDataE !== 32'h0000_005a) ||
                        (dut.SrcBE !== 32'b0) ||
                        (dut.ALUResultE !== 32'h0000_0120))
                        $fatal(1, "FAIL simultaneous STORE forwarding A/B");
                    seen_double_forward = 1'b1;
                end
                32'd124: begin
                    if ((dut.u_riscv_core.ForwardBE !== 2'b10) ||
                        (dut.WriteDataE !== 32'd2))
                        $fatal(1, "FAIL M priority over W for STORE data");
                    seen_m_priority = 1'b1;
                end
                32'd140: begin
                    if ((dut.u_riscv_core.ForwardAE !== 2'b00) ||
                        (dut.SrcAE !== 32'h0000_0128))
                        $fatal(1, "FAIL STORE operand after WB to Decode bypass");
                    seen_wb_decode_execute = 1'b1;
                end
                32'd168: begin
                    if ((dut.ALUResultE !== 32'h0000_0139) ||
                        (dut.StoreControlE !== 3'b001))
                        $fatal(1, "FAIL misaligned SH address generation");
                end
                32'd172: begin
                    if ((dut.ALUResultE !== 32'h0000_013a) ||
                        (dut.StoreControlE !== 3'b010))
                        $fatal(1, "FAIL misaligned SW address generation");
                end
                32'd180: begin
                    if (dut.MemWriteE || dut.RegWriteE)
                        $fatal(1, "FAIL invalid STORE funct3=011 reached Execute active");
                end
                32'd184: begin
                    if (dut.MemWriteE || dut.RegWriteE)
                        $fatal(1, "FAIL invalid STORE funct3=111 reached Execute active");
                end
                default: begin
                end
            endcase

            if ((dut.PCD == 32'd140) && dut.u_riscv_core.RegWriteW &&
                (dut.u_riscv_core.RdW == 5'd7)) begin
                if ((dut.Rs1D !== 5'd7) ||
                    (dut.RD1D !== dut.u_riscv_core.u_datapath.ResultW) ||
                    (dut.RD1D !== 32'h0000_0128))
                    $fatal(1, "FAIL WB to Decode bypass for STORE base");
                seen_wb_decode = 1'b1;
            end

            if ((dut.PCE == 32'd148) && dut.BranchE) begin
                if (!dut.u_riscv_core.PCSrcE || !dut.u_riscv_core.FlushD ||
                    !dut.u_riscv_core.FlushE || (dut.PCD !== 32'd152) ||
                    !dut.u_riscv_core.MemWriteD)
                    $fatal(1, "FAIL wrong-path STORE was not selected for flush");
                seen_wrong_path_flush = 1'b1;
            end

            if (dut.PCD == 32'd180) begin
                if ((dut.OpD !== 7'b0100011) || (dut.Funct3D !== 3'b011) ||
                    dut.u_riscv_core.MemWriteD || dut.u_riscv_core.RegWriteD)
                    $fatal(1, "FAIL invalid STORE funct3=011 decode");
                seen_invalid_011 = 1'b1;
            end
            if (dut.PCD == 32'd184) begin
                if ((dut.OpD !== 7'b0100011) || (dut.Funct3D !== 3'b111) ||
                    dut.u_riscv_core.MemWriteD || dut.u_riscv_core.RegWriteD)
                    $fatal(1, "FAIL invalid STORE funct3=111 decode");
                seen_invalid_111 = 1'b1;
            end
        end
    end

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        store_count = 0;
        suppressed_count = 0;
        seen_double_forward = 1'b0;
        seen_m_priority = 1'b0;
        seen_wb_decode = 1'b0;
        seen_wb_decode_execute = 1'b0;
        seen_positive_offset = 1'b0;
        seen_negative_offset = 1'b0;
        seen_x0_base = 1'b0;
        seen_wrong_path_flush = 1'b0;
        seen_invalid_011 = 1'b0;
        seen_invalid_111 = 1'b0;

        for (integer m = 0; m < DMEM_WORDS; m = m + 1) begin
            expected_memory[m] = 32'b0;
            expected_memory_valid[m] = 1'b0;
        end

        expected_program[0]  = encode_addi(12'sd256, 5'd0, 5'd6);
        expected_program[1]  = encode_store(12'sd0, 5'd0, 5'd6, 3'b010);
        expected_program[2]  = encode_addi(12'sh011, 5'd0, 5'd5);
        expected_program[3]  = encode_store(12'sd0, 5'd5, 5'd6, 3'b000);
        expected_program[4]  = encode_addi(12'sh022, 5'd0, 5'd5);
        expected_program[5]  = encode_store(12'sd1, 5'd5, 5'd6, 3'b000);
        expected_program[6]  = encode_addi(12'sh033, 5'd0, 5'd5);
        expected_program[7]  = encode_store(12'sd2, 5'd5, 5'd6, 3'b000);
        expected_program[8]  = encode_addi(12'sh044, 5'd0, 5'd5);
        expected_program[9]  = encode_store(12'sd3, 5'd5, 5'd6, 3'b000);
        expected_program[10] = encode_store(12'sd4, 5'd0, 5'd6, 3'b010);
        expected_program[11] = encode_lui(20'h00001, 5'd5);
        expected_program[12] = encode_addi(12'sh122, 5'd5, 5'd5);
        expected_program[13] = encode_store(12'sd4, 5'd5, 5'd6, 3'b001);
        expected_program[14] = encode_lui(20'h00003, 5'd5);
        expected_program[15] = encode_addi(12'sh344, 5'd5, 5'd5);
        expected_program[16] = encode_store(12'sd6, 5'd5, 5'd6, 3'b001);
        expected_program[17] = encode_lui(20'hdeadc, 5'd5);
        expected_program[18] = encode_addi(12'shbef, 5'd5, 5'd5);
        expected_program[19] = encode_store(12'sd8, 5'd5, 5'd6, 3'b010);
        expected_program[20] = encode_store(12'sd12, 5'd5, 5'd6, 3'b010);
        expected_program[21] = encode_store(12'sd16, 5'd0, 5'd6, 3'b010);
        expected_program[22] = encode_store(12'sd0, 5'd5, 5'd0, 3'b010);
        expected_program[23] = encode_lui(20'h00001, 5'd2);
        expected_program[24] = encode_addi(12'sh800, 5'd2, 5'd2);
        expected_program[25] = encode_store(12'shffc, 5'd5, 5'd2, 3'b010);
        expected_program[26] = encode_addi(12'sh05a, 5'd0, 5'd5);
        expected_program[27] = encode_addi(12'sh120, 5'd0, 5'd6);
        expected_program[28] = encode_store(12'sd0, 5'd5, 5'd6, 3'b010);
        expected_program[29] = encode_addi(12'sd1, 5'd0, 5'd5);
        expected_program[30] = encode_addi(12'sd2, 5'd0, 5'd5);
        expected_program[31] = encode_store(12'sd292, 5'd5, 5'd0, 3'b010);
        expected_program[32] = encode_addi(12'sh128, 5'd0, 5'd7);
        expected_program[33] = encode_addi(12'sd0, 5'd0, 5'd9);
        expected_program[34] = encode_addi(12'sd0, 5'd0, 5'd9);
        expected_program[35] = encode_store(12'sd0, 5'd5, 5'd7, 3'b010);
        expected_program[36] = encode_store(12'sd304, 5'd0, 5'd0, 3'b010);
        expected_program[37] = encode_branch(13'sd12, 5'd0, 5'd0, 3'b000);
        expected_program[38] = encode_store(12'sd304, 5'd5, 5'd0, 3'b010);
        expected_program[39] = encode_addi(12'sd9, 5'd0, 5'd10);
        expected_program[40] = encode_store(12'sd308, 5'd0, 5'd0, 3'b010);
        expected_program[41] = encode_store(12'sd312, 5'd5, 5'd0, 3'b010);
        expected_program[42] = encode_store(12'sd313, 5'd5, 5'd0, 3'b001);
        expected_program[43] = encode_store(12'sd314, 5'd5, 5'd0, 3'b010);
        expected_program[44] = encode_store(12'sd316, 5'd0, 5'd0, 3'b010);
        expected_program[45] = encode_store(12'sd316, 5'd5, 5'd0, 3'b011);
        expected_program[46] = encode_store(12'sd316, 5'd5, 5'd0, 3'b111);
        expected_program[47] = encode_addi(12'sd123, 5'd0, 5'd31);
        expected_program[48] = encode_store(12'sd31, 5'd5, 5'd6, 3'b000);
        expected_program[49] = encode_addi(12'sd0, 5'd0, 5'd0);
        expected_program[50] = encode_addi(12'sd0, 5'd0, 5'd0);
        expected_program[51] = encode_addi(12'sd0, 5'd0, 5'd0);
        expected_program[52] = encode_addi(12'sd0, 5'd0, 5'd0);

        #1;
        for (integer i = 0; i < PROGRAM_WORDS; i = i + 1) begin
            if (dut.u_instruction_memory.mem[i] !== expected_program[i])
                $fatal(1, "FAIL IMEM word %0d: hex=%h encoded=%h",
                       i, dut.u_instruction_memory.mem[i], expected_program[i]);
        end

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        repeat (65) @(posedge clk);
        @(negedge clk);

        if ((store_count != 21) || (suppressed_count != 2))
            $fatal(1, "FAIL store counts: enabled=%0d suppressed=%0d",
                   store_count, suppressed_count);
        if (!seen_double_forward || !seen_m_priority || !seen_wb_decode ||
            !seen_wb_decode_execute || !seen_positive_offset ||
            !seen_negative_offset || !seen_x0_base ||
            !seen_wrong_path_flush || !seen_invalid_011 || !seen_invalid_111)
            $fatal(1, "FAIL: a required STORE scenario was not observed");

        if (physical_word(32'h100 >> 2) !== 32'h4433_2211)
            $fatal(1, "FAIL SB lanes/little-endian result");
        if (physical_word(32'h104 >> 2) !== 32'h3344_1122)
            $fatal(1, "FAIL SH lanes/little-endian result");
        if ((physical_word(32'h108 >> 2) !== 32'hdead_beef) ||
            (physical_word(32'h10c >> 2) !== 32'hdead_beef) ||
            (physical_word(32'h000 >> 2) !== 32'hdead_beef) ||
            (physical_word(32'h7fc >> 2) !== 32'hdead_beef))
            $fatal(1, "FAIL SW data, offset, x0 base or upper boundary");
        if ((physical_word(32'h110 >> 2) !== 32'b0) ||
            (physical_word(32'h120 >> 2) !== 32'h0000_005a) ||
            (physical_word(32'h124 >> 2) !== 32'h0000_0002) ||
            (physical_word(32'h128 >> 2) !== 32'h0000_0002))
            $fatal(1, "FAIL zero data or forwarding STORE results");
        if ((physical_word(32'h130 >> 2) !== 32'b0) ||
            (physical_word(32'h138 >> 2) !== 32'h0000_0002) ||
            (physical_word(32'h13c >> 2) !== 32'h0200_0000))
            $fatal(1, "FAIL wrong-path, misaligned or invalid STORE protection");
        if (dut.u_riscv_core.u_datapath.u_register_file.regs[31] !== 32'd123)
            $fatal(1, "FAIL STORE treated Instr[11:7] as rd");

        $display("PASS: SB/SH/SW lanes, little-endian and byte preservation");
        $display("PASS: address/data forwarding, M priority and WB-Decode bypass");
        $display("PASS: offsets, x0, boundary and safe misaligned policy");
        $display("PASS: wrong-path and invalid stores have no side effects");
        $display("PASS: STORE checkpoint completed; LOAD remains unimplemented");
        $finish;
    end

endmodule
