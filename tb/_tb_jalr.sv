`timescale 1ns/1ps

// Teste end-to-end de JALR pelo topo do sistema. Todos os targets finais sao
// multiplos de 4; o tratamento futuro de target[1]=1 pertencera aos traps.
module tb_jalr;
    localparam integer PROGRAM_WORDS = 77;

    logic clk;
    logic reset;
    logic [31:0] expected_program [0:PROGRAM_WORDS-1];
    logic [31:0] isolated_instruction;
    logic [31:0] isolated_imm;
    integer redirect_count;
    integer jump_wb_count;
    integer link_consumer_count;
    logic saw_basic;
    logic saw_negative;
    logic saw_forward_m;
    logic saw_forward_w;
    logic saw_wb_decode;
    logic saw_wb_decode_execute;
    logic saw_jalr_x0;
    logic saw_invalid_decode;
    logic saw_invalid_execute;
    logic saw_call;
    logic saw_ret;
    logic saw_return_point;

    wire        PCSrcE     = dut.u_riscv_core.PCSrcE;
    wire        JalrD      = dut.u_riscv_core.JalrD;
    wire        JalrE      = dut.JalrE;
    wire [1:0]  ForwardAE  = dut.u_riscv_core.ForwardAE;
    wire [1:0]  ForwardBE  = dut.u_riscv_core.ForwardBE;
    wire        RegWriteW  = dut.u_riscv_core.u_datapath.RegWriteW;
    wire [1:0]  ResultSrcW = dut.u_riscv_core.u_datapath.ResultSrcW;
    wire [4:0]  RdW        = dut.u_riscv_core.u_datapath.RdW;
    wire [31:0] ResultW     = dut.u_riscv_core.u_datapath.ResultW;
    wire [31:0] RFRead1D   = dut.u_riscv_core.u_datapath.RFRead1D;
    wire [31:0] RFRead2D   = dut.u_riscv_core.u_datapath.RFRead2D;

    riscv_system_top #(
        .IMEM_INIT_FILE ("../mem/jalr.hex")
    ) dut (
        .clk   (clk),
        .reset (reset)
    );

    // O JALR usa o mesmo imediato I do ADDI. Esta instancia isolada verifica
    // os limites sem tentar buscar enderecos fora da IMEM.
    extend u_isolated_extend (
        .InstrD  (isolated_instruction[31:7]),
        .ImmSrcD (3'b000),
        .ImmExtD (isolated_imm)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function automatic logic [31:0] encode_addi(
        input logic [11:0] immediate,
        input logic [4:0] rs1,
        input logic [4:0] rd
    );
        encode_addi = {immediate, rs1, 3'b000, rd, 7'b0010011};
    endfunction

    function automatic logic [31:0] encode_indexed_addi(
        input integer immediate,
        input integer rd
    );
        logic [11:0] immediate_bits;
        logic [4:0]  rd_bits;
        begin
            // Os recortes deixam explicitas as larguras usadas nos loops que
            // montam sentinelas, sem depender de truncamento implicito.
            immediate_bits = immediate[11:0];
            rd_bits = rd[4:0];
            encode_indexed_addi = encode_addi(immediate_bits, 5'd0, rd_bits);
        end
    endfunction

    function automatic logic [31:0] encode_jalr(
        input logic [11:0] immediate,
        input logic [4:0] rs1,
        input logic [4:0] rd
    );
        encode_jalr = {immediate, rs1, 3'b000, rd, 7'b1100111};
    endfunction

    function automatic logic [31:0] encode_jal(
        input integer offset,
        input logic [4:0] rd
    );
        logic [20:0] offset_bits;
        begin
            offset_bits = offset[20:0];
            encode_jal = {offset_bits[20], offset_bits[10:1], offset_bits[11],
                          offset_bits[19:12], rd, 7'b1101111};
        end
    endfunction

    task automatic check_common;
        begin
            if ({dut.u_riscv_core.StallF, dut.u_riscv_core.StallD} !== 2'b00)
                $fatal(1, "FAIL: JALR introduziu stall");
            if ({dut.u_riscv_core.FlushD, dut.u_riscv_core.FlushE} !==
                {2{PCSrcE}})
                $fatal(1, "FAIL: flushes nao acompanham PCSrcE");
            if (PCSrcE !== dut.JumpE)
                $fatal(1, "FAIL: PCSrcE deixou de representar JumpE");
            if ((ForwardAE === 2'b11) || (ForwardBE === 2'b11))
                $fatal(1, "FAIL: codigo 11 de forwarding");
            if ((dut.MemWriteM !== 1'b0) || (dut.u_data_memory.en !== 1'b0) ||
                (dut.u_data_memory.wstrb !== 4'b0000))
                $fatal(1, "FAIL: acesso inesperado a DMEM");

            // x20..x31 sao sentinelas de caminhos errados. A unica excecao e
            // o JALR invalido com Rd=23, cujo RegWrite obrigatoriamente e zero.
            if (RegWriteW && (RdW >= 5'd20))
                $fatal(1, "FAIL: wrong-path chegou ao WB para x%0d", RdW);
        end
    endtask

    task automatic check_jalr_execute(
        input logic [31:0] expected_pce,
        input logic [31:0] expected_src_a,
        input logic [31:0] expected_imm,
        input logic [31:0] expected_alu,
        input logic [31:0] expected_target,
        input logic [1:0]  expected_forward,
        input logic [4:0]  expected_rd
    );
        begin
            if ((dut.PCE !== expected_pce) || (JalrE !== 1'b1) ||
                (dut.JumpE !== 1'b1) || (dut.ALUSrcE !== 1'b1) ||
                (dut.ALUControlE !== 4'b0000) ||
                (ForwardAE !== expected_forward) ||
                (dut.SrcAE !== expected_src_a) ||
                (dut.ImmExtE !== expected_imm) ||
                (dut.ALUResultE !== expected_alu) ||
                (dut.PCTargetE !== expected_target) ||
                (PCSrcE !== 1'b1) || (dut.RdE !== expected_rd) ||
                ({dut.u_riscv_core.FlushD, dut.u_riscv_core.FlushE} !== 2'b11))
                $fatal(1, "FAIL JALR Execute at PC=%0d", expected_pce);
        end
    endtask

    initial begin
        reset = 1'b1;
        redirect_count = 0;
        jump_wb_count = 0;
        link_consumer_count = 0;
        saw_basic = 1'b0;
        saw_negative = 1'b0;
        saw_forward_m = 1'b0;
        saw_forward_w = 1'b0;
        saw_wb_decode = 1'b0;
        saw_wb_decode_execute = 1'b0;
        saw_jalr_x0 = 1'b0;
        saw_invalid_decode = 1'b0;
        saw_invalid_execute = 1'b0;
        saw_call = 1'b0;
        saw_ret = 1'b0;
        saw_return_point = 1'b0;
        isolated_instruction = 32'b0;

        // Extremos assinados do imediato I usado pelo JALR.
        isolated_instruction = encode_jalr(12'h7ff, 5'd1, 5'd2);
        #1;
        if (isolated_imm !== 32'h0000_07ff)
            $fatal(1, "FAIL JALR immediate +2047");
        isolated_instruction = encode_jalr(12'h800, 5'd1, 5'd2);
        #1;
        if (isolated_imm !== 32'hffff_f800)
            $fatal(1, "FAIL JALR immediate -2048");
        $display("PASS: JALR I-immediate limits +2047 and -2048");

        for (integer i = 0; i < PROGRAM_WORDS; i = i + 1)
            expected_program[i] = encode_addi(12'd0, 5'd0, 5'd0);

        expected_program[0] = encode_addi(12'd39, 5'd0, 5'd5);
        for (integer i = 1; i < 5; i = i + 1)
            expected_program[i] = encode_addi(i[11:0], 5'd0, 5'd2);
        expected_program[5] = encode_jalr(12'd2, 5'd5, 5'd6);
        for (integer i = 6; i < 10; i = i + 1)
            expected_program[i] = encode_indexed_addi(i + 95, i + 14);
        expected_program[10] = encode_addi(12'd1, 5'd6, 5'd7);

        expected_program[11] = encode_addi(12'd81, 5'd0, 5'd8);
        for (integer i = 12; i < 16; i = i + 1)
            expected_program[i] = encode_addi(i[11:0], 5'd0, 5'd2);
        expected_program[16] = encode_jalr(12'hfff, 5'd8, 5'd9);
        for (integer i = 17; i < 20; i = i + 1)
            expected_program[i] = encode_indexed_addi(i + 88, i + 7);
        expected_program[20] = encode_addi(12'd1, 5'd9, 5'd10);

        expected_program[21] = encode_addi(12'd112, 5'd0, 5'd11);
        expected_program[22] = encode_jalr(12'd0, 5'd11, 5'd12);
        for (integer i = 23; i < 28; i = i + 1)
            expected_program[i] = encode_indexed_addi(i + 120, i - 3);
        expected_program[28] = encode_addi(12'd1, 5'd12, 5'd13);

        expected_program[29] = encode_addi(12'd148, 5'd0, 5'd14);
        expected_program[30] = encode_addi(12'd30, 5'd0, 5'd2);
        expected_program[31] = encode_jalr(12'd0, 5'd14, 5'd15);
        for (integer i = 32; i < 37; i = i + 1)
            expected_program[i] = encode_indexed_addi(i + 120, i - 12);
        expected_program[37] = encode_addi(12'd1, 5'd15, 5'd16);

        expected_program[38] = encode_addi(12'd188, 5'd0, 5'd17);
        expected_program[39] = encode_addi(12'd39, 5'd0, 5'd2);
        expected_program[40] = encode_addi(12'd40, 5'd0, 5'd2);
        expected_program[41] = encode_jalr(12'd0, 5'd17, 5'd18);
        for (integer i = 42; i < 47; i = i + 1)
            expected_program[i] = encode_indexed_addi(i + 120, i - 22);
        expected_program[47] = encode_addi(12'd1, 5'd18, 5'd19);

        expected_program[48] = encode_addi(12'd220, 5'd0, 5'd3);
        expected_program[49] = encode_jalr(12'd0, 5'd3, 5'd0);
        for (integer i = 50; i < 55; i = i + 1)
            expected_program[i] = encode_indexed_addi(i + 120, i - 30);
        expected_program[55] = encode_addi(12'd4, 5'd0, 5'd4);
        // Mesmo opcode de JALR, mas funct3=001: deve permanecer sem efeito.
        expected_program[56] = {12'd0, 5'd4, 3'b001, 5'd23, 7'b1100111};
        expected_program[57] = encode_addi(12'd1, 5'd4, 5'd4);

        expected_program[58] = encode_jal(40, 5'd1);
        expected_program[59] = encode_addi(12'd42, 5'd0, 5'd10);
        expected_program[60] = encode_jal(60, 5'd0);
        for (integer i = 61; i < 68; i = i + 1)
            expected_program[i] = encode_indexed_addi(i + 120, i - 41);
        expected_program[68] = encode_addi(12'd77, 5'd0, 5'd11);
        expected_program[69] = encode_jalr(12'd0, 5'd1, 5'd0); // ret
        for (integer i = 70; i < 75; i = i + 1)
            expected_program[i] = encode_indexed_addi(i + 120, i - 50);
        expected_program[75] = encode_addi(12'd88, 5'd0, 5'd12);
        expected_program[76] = encode_addi(12'd1, 5'd12, 5'd13);

        #1;
        for (integer i = 0; i < PROGRAM_WORDS; i = i + 1) begin
            if (dut.u_instruction_memory.mem[i] !== expected_program[i])
                $fatal(1, "FAIL encoding word %0d: hex=%h expected=%h",
                       i, dut.u_instruction_memory.mem[i], expected_program[i]);
        end
        for (integer i = PROGRAM_WORDS; i < 512; i = i + 1)
            dut.u_instruction_memory.mem[i] = 32'h0000_0013;
        $display("PASS: JALR program encodings checked independently");

        @(posedge clk);
        #1;
        if ((dut.PCF !== 32'b0) || (JalrE !== 1'b0) || (RegWriteW !== 1'b0))
            $fatal(1, "FAIL reset state");
        @(negedge clk);
        reset = 1'b0;

        for (integer cycle = 1; cycle <= 90; cycle = cycle + 1) begin
            @(posedge clk);
            #1;
            check_common();

            // Decoder valido e invalido sao observados na instrucao real.
            if ((dut.OpD == 7'b1100111) && (dut.PCD != 32'd224)) begin
                if ((JalrD !== 1'b1) || (dut.u_riscv_core.JumpD !== 1'b1) ||
                    (dut.u_riscv_core.RegWriteD !== 1'b1) ||
                    (dut.u_riscv_core.ResultSrcD !== 2'b10) ||
                    (dut.u_riscv_core.ALUSrcD !== 1'b1) ||
                    (dut.u_riscv_core.ALUControlD !== 4'b0000) ||
                    (dut.u_riscv_core.ImmSrcD !== 3'b000))
                    $fatal(1, "FAIL valid JALR Decode at PC=%0d", dut.PCD);
            end
            if (dut.PCD == 32'd224) begin
                if ((dut.Funct3D !== 3'b001) || (JalrD !== 1'b0) ||
                    (dut.u_riscv_core.JumpD !== 1'b0) ||
                    (dut.u_riscv_core.RegWriteD !== 1'b0) ||
                    (dut.u_riscv_core.MemWriteD !== 1'b0))
                    $fatal(1, "FAIL invalid JALR Decode");
                saw_invalid_decode = 1'b1;
            end

            // Produtor em WB e JALR em Decode: ResultW deve vencer RFRead1D.
            if ((dut.PCD == 32'd164) && RegWriteW && (RdW == 5'd17)) begin
                if ((ResultW !== 32'd188) || (dut.Rs1D !== 5'd17) ||
                    (RFRead1D === 32'd188) || (dut.RD1D !== 32'd188))
                    $fatal(1, "FAIL WB->Decode for JALR base");
                saw_wb_decode = 1'b1;
                $display("PASS: JALR base receives WB->Decode bypass");
            end

            if (PCSrcE) begin
                redirect_count = redirect_count + 1;
                case (dut.PCE)
                    32'd20: begin
                        check_jalr_execute(32'd20, 32'd39, 32'd2, 32'd41,
                                           32'd40, 2'b00, 5'd6);
                        saw_basic = 1'b1;
                        $display("PASS: JALR clears bit 0: ALU=41 target=40");
                    end
                    32'd64: begin
                        check_jalr_execute(32'd64, 32'd81, 32'hffff_ffff,
                                           32'd80, 32'd80, 2'b00, 5'd9);
                        saw_negative = 1'b1;
                    end
                    32'd88: begin
                        check_jalr_execute(32'd88, 32'd112, 32'd0, 32'd112,
                                           32'd112, 2'b10, 5'd12);
                        saw_forward_m = 1'b1;
                        $display("PASS: JALR base forwarded from EX/MEM");
                    end
                    32'd124: begin
                        check_jalr_execute(32'd124, 32'd148, 32'd0, 32'd148,
                                           32'd148, 2'b01, 5'd15);
                        saw_forward_w = 1'b1;
                        $display("PASS: JALR base forwarded from MEM/WB");
                    end
                    32'd164: begin
                        check_jalr_execute(32'd164, 32'd188, 32'd0, 32'd188,
                                           32'd188, 2'b00, 5'd18);
                        if (dut.RD1E !== 32'd188)
                            $fatal(1, "FAIL bypassed base was not captured by ID/EX");
                        saw_wb_decode_execute = 1'b1;
                    end
                    32'd196: begin
                        check_jalr_execute(32'd196, 32'd220, 32'd0, 32'd220,
                                           32'd220, 2'b10, 5'd0);
                        saw_jalr_x0 = 1'b1;
                    end
                    32'd232: begin
                        if ((JalrE !== 1'b0) || (dut.PCTargetE !== 32'd272) ||
                            (dut.u_riscv_core.u_datapath.PCRelativeTargetE !== 32'd272) ||
                            (dut.RdE !== 5'd1))
                            $fatal(1, "FAIL JAL call target/link");
                        saw_call = 1'b1;
                    end
                    32'd276: begin
                        check_jalr_execute(32'd276, 32'd236, 32'd0, 32'd236,
                                           32'd236, 2'b00, 5'd0);
                        saw_ret = 1'b1;
                        $display("PASS: ret is jalr x0,0(ra) and targets PC=236");
                    end
                    32'd240: begin
                        if ((JalrE !== 1'b0) || (dut.PCTargetE !== 32'd300) ||
                            (dut.RdE !== 5'd0))
                            $fatal(1, "FAIL JAL after return");
                    end
                    default: $fatal(1, "FAIL unexpected redirect PC=%0d", dut.PCE);
                endcase
            end

            // Funct3 invalido atravessa Execute sem redirecionar ou escrever.
            if (dut.PCE == 32'd224) begin
                if ((JalrE !== 1'b0) || (dut.JumpE !== 1'b0) ||
                    (PCSrcE !== 1'b0) || (dut.RegWriteE !== 1'b0))
                    $fatal(1, "FAIL invalid JALR Execute");
                saw_invalid_execute = 1'b1;
            end

            // Cada JALR que escreve rd encontra seu consumidor do target em ID.
            if (RegWriteW && (ResultSrcW == 2'b10)) begin
                jump_wb_count = jump_wb_count + 1;
                case (dut.u_riscv_core.u_datapath.PCPlus4W)
                    32'd24: begin
                        if ((RdW !== 5'd6) || (ResultW !== 32'd24) ||
                            (dut.PCD !== 32'd40) || (dut.Rs1D !== 5'd6) ||
                            (dut.RD1D !== 32'd24) || (RFRead1D === 32'd24))
                            $fatal(1, "FAIL basic JALR link consumer in Decode");
                        link_consumer_count = link_consumer_count + 1;
                    end
                    32'd68: begin
                        if ((RdW !== 5'd9) || (ResultW !== 32'd68) ||
                            (dut.PCD !== 32'd80) || (dut.RD1D !== 32'd68))
                            $fatal(1, "FAIL negative JALR link consumer");
                        link_consumer_count = link_consumer_count + 1;
                    end
                    32'd92: begin
                        if ((RdW !== 5'd12) || (ResultW !== 32'd92) ||
                            (dut.PCD !== 32'd112) || (dut.RD1D !== 32'd92))
                            $fatal(1, "FAIL M-forward JALR link consumer");
                        link_consumer_count = link_consumer_count + 1;
                    end
                    32'd128: begin
                        if ((RdW !== 5'd15) || (ResultW !== 32'd128) ||
                            (dut.PCD !== 32'd148) || (dut.RD1D !== 32'd128))
                            $fatal(1, "FAIL W-forward JALR link consumer");
                        link_consumer_count = link_consumer_count + 1;
                    end
                    32'd168: begin
                        if ((RdW !== 5'd18) || (ResultW !== 32'd168) ||
                            (dut.PCD !== 32'd188) || (dut.RD1D !== 32'd168))
                            $fatal(1, "FAIL WB-Decode JALR link consumer");
                        link_consumer_count = link_consumer_count + 1;
                    end
                    32'd200, 32'd244, 32'd280: begin
                        if ((RdW !== 5'd0) || (dut.RD1D !== RFRead1D) ||
                            (dut.RD2D !== RFRead2D))
                            $fatal(1, "FAIL jump x0 created WB-Decode bypass");
                    end
                    32'd236: begin
                        if ((RdW !== 5'd1) || (ResultW !== 32'd236) ||
                            (dut.PCD !== 32'd272))
                            $fatal(1, "FAIL JAL call link in ra");
                    end
                    default: $fatal(1, "FAIL unexpected jump in WB");
                endcase
            end

            // Consumidores imediatos chegaram a EX sem depender de forwarding.
            case (dut.PCE)
                32'd40:  if ((ForwardAE !== 2'b00) || (dut.SrcAE !== 32'd24) ||
                              (dut.ALUResultE !== 32'd25)) $fatal(1, "FAIL link x6 consumer");
                32'd80:  if ((ForwardAE !== 2'b00) || (dut.SrcAE !== 32'd68) ||
                              (dut.ALUResultE !== 32'd69)) $fatal(1, "FAIL link x9 consumer");
                32'd112: if ((ForwardAE !== 2'b00) || (dut.SrcAE !== 32'd92) ||
                              (dut.ALUResultE !== 32'd93)) $fatal(1, "FAIL link x12 consumer");
                32'd148: if ((ForwardAE !== 2'b00) || (dut.SrcAE !== 32'd128) ||
                              (dut.ALUResultE !== 32'd129)) $fatal(1, "FAIL link x15 consumer");
                32'd188: if ((ForwardAE !== 2'b00) || (dut.SrcAE !== 32'd168) ||
                              (dut.ALUResultE !== 32'd169)) $fatal(1, "FAIL link x18 consumer");
                32'd236: begin
                    if (dut.ALUResultE !== 32'd42)
                        $fatal(1, "FAIL return point instruction");
                    saw_return_point = 1'b1;
                end
                default: begin
                end
            endcase
        end

        if ((redirect_count != 9) || (jump_wb_count != 9) ||
            (link_consumer_count != 5) || !saw_basic || !saw_negative ||
            !saw_forward_m || !saw_forward_w || !saw_wb_decode ||
            !saw_wb_decode_execute || !saw_jalr_x0 ||
            !saw_invalid_decode || !saw_invalid_execute ||
            !saw_call || !saw_ret || !saw_return_point)
            $fatal(1, "FAIL: not all JALR checkpoints were observed");

        if ((dut.u_riscv_core.u_datapath.u_register_file.regs[1]  !== 32'd236) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[4]  !== 32'd5) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[5]  !== 32'd39) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[6]  !== 32'd24) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[7]  !== 32'd25) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[8]  !== 32'd81) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[9]  !== 32'd68) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[10] !== 32'd42) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[11] !== 32'd77) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[12] !== 32'd88) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[13] !== 32'd89) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[15] !== 32'd128) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[16] !== 32'd129) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[17] !== 32'd188) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[18] !== 32'd168) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[19] !== 32'd169) ||
            (dut.RD1D !== 32'b0) || (dut.RD2D !== 32'b0))
            $fatal(1, "FAIL final architectural register values");

        $display("PASS: JALR positive/negative, forwarding, bypass, x0 and real RET");
        $finish;
    end

    initial begin
        #3000;
        $fatal(1, "FAIL: JALR test timeout");
    end
endmodule
